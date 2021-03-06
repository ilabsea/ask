defmodule Ask.Runtime.Broker do
  use GenServer
  use Timex
  import Ecto.Query
  import Ecto
  require Ask.RespondentStats
  alias Ask.{Repo, Survey, Respondent, RespondentStats, RespondentDispositionHistory, RespondentGroup, QuotaBucket, Logger, Schedule}
  alias Ask.Runtime.{Session, Reply, Flow, SessionMode, SessionModeProvider}
  alias Ask.QuotaBucket

  @poll_interval :timer.minutes(1)
  @server_ref {:global, __MODULE__}

  def server_ref, do: @server_ref

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @server_ref)
  end

  # Makes the borker performs a poll on the surveys.
  # This method is intended to be used by tests.
  def poll do
    GenServer.call(@server_ref, :poll)
  end

  def init(_args) do
    :timer.send_after(1000, :poll)
    Logger.info "Broker started. Default batch size=#{default_batch_size()}. Limit per minute=#{batch_limit_per_minute()}."
    {:ok, nil}
  end

  def handle_info(:poll, state, now) do
    try do
      mark_stalled_for_eight_hours_respondents_as_failed()

      Repo.all(from r in Respondent, where: r.state == "active" and r.timeout_at <= ^now, limit: ^batch_limit_per_minute())
      |> Enum.each(&retry_respondent(&1))

      all_running_surveys()
      |> Enum.filter(&Schedule.intersect?(&1.schedule, now))
      |> Enum.each(&poll_survey/1)

      {:noreply, state}
    after
      :timer.send_after(@poll_interval, :poll)
    end
  end

  def handle_info(:poll, state) do
    handle_info(:poll, state, Timex.now)
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def handle_call(:poll, _from, state) do
    handle_info(:poll, state)
    {:reply, :ok, state}
  end

  defp all_running_surveys do
    Repo.all(from s in Survey, where: s.state == "running")
  end

  defp mark_stalled_for_eight_hours_respondents_as_failed do
    eight_hours_ago = Timex.now |> Timex.shift(hours: -8)

    (from r in Respondent,
      where: r.state == "stalled",
      where: r.updated_at <= ^eight_hours_ago)
    |> Repo.all
    |> Enum.each(fn respondent ->
      update_respondent(respondent, :failed)
    end)
  end

  def channel_failed(respondent, reason \\ "failed") do
    session = respondent.session
    if session do
      session = session |> Session.load
      case Session.channel_failed(session, reason) do
        :ok -> :ok
        :failed ->
          update_respondent(respondent, :failed)
      end
    else
      :ok
    end
  end

  def contact_attempt_expired(respondent, reason) do
    session = respondent.session
    if session do
      response = session
        |> Session.load
        |> Session.contact_attempt_expired(reason)

      update_respondent(respondent, response, nil)
    end
    :ok
  end

  def delivery_confirm(respondent, title) do
    delivery_confirm(respondent, title, nil)
  end

  def delivery_confirm(respondent, title, mode) do
    unless respondent.session == nil do
      session = respondent.session |> Session.load
      session_mode =
        case session_mode(respondent, session, mode) do
          :invalid_mode -> session.current_mode
          mode -> mode
        end
      Session.delivery_confirm(session, title, session_mode)
      update_respondent_disposition(session, "contacted")
    end
  end

  defp respondents_by_state(survey) do
    by_state_defaults = %{
      "active" => 0,
      "pending" => 0,
      "completed" => 0,
      "stalled" => 0,
      "rejected" => 0,
      "failed" => 0,
    }

    RespondentStats.respondent_count(survey_id: ^survey.id, by: :state)
      |> Enum.into(by_state_defaults)
  end

  defp poll_survey(survey) do
    try do
      by_state = respondents_by_state(survey)
      %{
        "active" => active,
        "pending" => pending,
        "completed" => completed,
        "stalled" => stalled,
      } = by_state

      reached_quotas = reached_quotas?(survey)
      survey_completed = survey.cutoff <= completed || reached_quotas
      batch_size = batch_size(survey, by_state)
      Logger.info "Polling survey #{survey.id} (active=#{active}, pending=#{pending}, completed=#{completed}, stalled=#{stalled}, batch_size=#{batch_size})"

      cond do
        (active == 0 && ((pending + stalled) == 0 || survey_completed)) ->
          Logger.info "Survey #{survey.id} completed"
          complete(survey)

        (active + stalled) < batch_size && pending > 0 && !survey_completed ->
          count = batch_size - (active + stalled)
          Logger.info "Survey #{survey.id}. Starting up to #{count} respondents."
          start_some(survey, count)

        true -> :ok
      end
    rescue
      e ->
        if Mix.env == :test do
          IO.inspect e
          IO.inspect System.stacktrace()
          raise e
        end
        Logger.error "Error occurred while polling survey (id: #{survey.id}): #{inspect e} #{inspect System.stacktrace}"
        Sentry.capture_exception(e, [
          stacktrace: System.stacktrace(),
          extra: %{survey_id: survey.id}])
    end
  end

  defp reached_quotas?(survey) do
    case survey.quota_vars do
      [] -> false
      _ ->
        survey_id = survey.id
        Repo.one(from q in QuotaBucket,
          where: q.survey_id == ^survey_id,
          where: q.count < q.quota,
          select: count(q.id)) == 0
    end
  end

  defp complete(survey) do
    Repo.update Survey.changeset(survey, %{state: "terminated", exit_code: 0, exit_message: "Successfully completed"})
    set_stalled_respondents_as_failed(survey)
  end

  defp set_stalled_respondents_as_failed(survey) do
    from(r in assoc(survey, :respondents), where: r.state == "stalled")
    |> Repo.update_all(set: [state: "failed", session: nil, timeout_at: nil])
  end

  defp start_some(survey, count) do
    count = Enum.min([batch_limit_per_minute(), count])

    (from r in assoc(survey, :respondents),
      where: r.state == "pending",
      limit: ^count)
    |> preload(respondent_group: [respondent_group_channels: :channel])
    |> Repo.all
    |> Enum.each(&start(survey, &1))
  end

  def retry_respondent(respondent) do
    session = respondent.session |> Session.load

    Repo.transaction(fn ->
      try do
        handle_session_step(Session.timeout(session))
      rescue
        e in Ecto.StaleEntryError ->
          # Maybe sync_step or another action was executed while the timeout was executed,
          # and that means the respondent reply, so we don't need to apply the timeout anymore
          Repo.rollback(e)
      end
    end)
  end

  defp start(survey, respondent) do
    survey = Repo.preload(survey, [:questionnaires])
    group = respondent.respondent_group

    {questionnaire, mode} = select_questionnaire_and_mode(survey)

    {primary_mode, fallback_mode} = case mode do
      [primary] -> {primary, nil}
      [primary, fallback] -> {primary, fallback}
    end

    # Set respondent questionnaire and mode
    respondent = respondent
    |> Respondent.changeset(%{questionnaire_id: questionnaire.id, mode: mode, disposition: "queued"})
    |> Repo.update!
    |> create_disposition_history(respondent.disposition, primary_mode)

    primary_channel = RespondentGroup.primary_channel(group, mode)
    fallback_channel = RespondentGroup.fallback_channel(group, mode)

    retries = Survey.retries_configuration(survey, primary_mode)
    fallback_retries = case fallback_channel do
      nil -> []
      _ -> Survey.retries_configuration(survey, fallback_mode)
    end

    fallback_delay = Survey.fallback_delay(survey) || Session.default_fallback_delay

    handle_session_step(Session.start(questionnaire, respondent, primary_channel, primary_mode, survey.schedule, retries, fallback_channel, fallback_mode, fallback_retries, fallback_delay, survey.count_partial_results))
  end

  defp select_questionnaire_and_mode(%Survey{comparisons: []} = survey) do
    {hd(survey.questionnaires), hd(survey.mode)}
  end

  defp select_questionnaire_and_mode(%Survey{comparisons: comparisons} = survey) do
    # Get a random value between 0 and 100
    rand = :rand.uniform() * 100

    # Traverse comparisons:
    #
    # - keep the total ratio so far across visited comparisons
    # - included comparisons are those whose total ratio so far is greater than the rand value
    # - in the end we keep the first comparison that is included
    #
    # For example, if the ratios are [10, 25, 35, 30] and we
    # get a random value of 45, the result of the map_reduce will
    # be [{10, false}, {25, false}, {35, true}, {30, true}] because
    # after the entry with ratio 25 the total accumulated ratio will be
    # 10 + 25 + 35 = 70 >= 45. Then we keep the first one that's true.
    {candidates, _} = comparisons
    |> Enum.map_reduce(0, fn (comparison, total_count) ->
      ratio = comparison["ratio"]
      total_count = total_count + (ratio || 0)
      included = total_count >= rand
      {{comparison, included}, total_count}
    end)

    candidate = candidates
    |> Enum.find(fn {_, included} -> included end)

    if candidate do
      {comparison, _} = candidate
      questionnaire = survey.questionnaires
      |> Enum.find(fn q -> q.id == comparison["questionnaire_id"] end)
      mode = comparison["mode"]
      {questionnaire, mode}
    else
      # Fall back to first questionnaire and mode, in case
      # the comparisons ratios don't add up 100
      {hd(survey.questionnaires), hd(survey.mode)}
    end
  end

  def sync_step(respondent, reply, mode \\ nil) do
    session = respondent.session |> Session.load
    session_mode = session_mode(respondent, session, mode)
    sync_step_internal(session, reply, session_mode)
  end

  defp session_mode(_respondent, session, nil) do
    session.current_mode
  end

  defp session_mode(respondent, session, mode) do
    if mode == session.current_mode |> SessionMode.mode do
      session.current_mode
    else
      group = (respondent |> Repo.preload(:respondent_group)).respondent_group
      channel_group = (group |> Repo.preload([respondent_group_channels: :channel])).respondent_group_channels
      |> Enum.find(fn c -> c.mode == mode end)

      if channel_group do
        SessionModeProvider.new(mode, channel_group.channel, [])
      else
        :invalid_mode
      end
    end
  end

  # We expose this method so we can test that if a stale respondent is
  # passed, it's reloaded and the action is retried (this can happen
  # if a timeout happens in between this call)
  def sync_step_internal(session, reply) do
    sync_step_internal(session, reply, session.current_mode)
  end

  def sync_step_internal(_, _, :invalid_mode) do
    :end
  end

  def sync_step_internal(session, reply, session_mode) do
    transaction_result = Repo.transaction(fn ->
      try do
        session = cond do
          reply == Flow.Message.no_reply ->
            # no_reply is produced, for example, from a timeout in Verboice
            session
          reply == Flow.Message.answer ->
            update_respondent_disposition(session, "contacted")
          true ->
            update_respondent_disposition(session, "started")
        end

        reply = mask_phone_number(session.respondent, reply)
        handle_session_step(Session.sync_step(session, reply, session_mode))
      rescue
        e in Ecto.StaleEntryError ->
          Repo.rollback(e)
        e ->
          # If we uncomment this a test will fail (the one that cheks that nothing breaks),
          # but this could help you find a bug in a particular test that is not working.
          # if Mix.env == :test do
          #   IO.inspect e
          #   IO.inspect System.stacktrace()
          #   raise e
          # end
          respondent = Repo.get(Respondent, session.respondent.id)
          Logger.error "Error occurred while processing sync step (survey_id: #{respondent.survey_id}, respondent_id: #{respondent.id}): #{inspect e} #{inspect System.stacktrace}"
          Sentry.capture_exception(e, [
            stacktrace: System.stacktrace(),
            extra: %{survey_id: respondent.survey_id, respondent_id: respondent.id}])

          try do
            handle_session_step({:failed, respondent})
          rescue
            e ->
              if Mix.env == :test do
                IO.inspect e
                IO.inspect System.stacktrace()
                raise e
              end
              :end
          end
      end
    end)

    case transaction_result do
      {:ok, response} ->
        response
      {:error, %Ecto.StaleEntryError{}} ->
        respondent = Repo.get(Respondent, session.respondent.id)
        # Maybe timeout or another action was executed while sync_step was executed, so we need to retry
        sync_step(respondent, reply, session_mode)
      value ->
        value
    end
  end

  def mask_phone_number(%Respondent{} = respondent, {:reply, response}) do
    pii = respondent.sanitized_phone_number |> String.slice(-6..-1)
    # pii can be empty if the sanitized_phone_number has less than 5 digits,
    # that could be mostly to the case of a randomly generated phone number form a test
    # String.contains? returns true for empty strings
    masked_response = if String.length(pii) != 0 && contains_phone_number(response, pii) do
      mask_phone_number(response, phone_number_matcher(pii), pii)
    else
      response
    end

    Flow.Message.reply(masked_response)
  end
  def mask_phone_number(_, reply), do: reply
  def mask_phone_number(response, regex, pii) do
    masked_response = response |> String.replace(regex, "\\1#\\3#\\5#\\7#\\9#\\11#\\13")

    if contains_phone_number(masked_response, pii) do
      mask_phone_number(masked_response, regex, pii)
    else
      masked_response
    end
  end

  defp contains_phone_number(response, pii) do
    String.contains?(Respondent.sanitize_phone_number(response), pii)
  end

  defp phone_number_matcher(pii) do
    String.graphemes(pii)
      |> Enum.reduce("(.*)", fn(digit, regex) ->
        "#{regex}(#{digit})(.*)"
      end)
      |> Regex.compile!
  end

  defp handle_session_step({:ok, session, reply, timeout, respondent}) do
    update_respondent(respondent, {:ok, session, timeout}, Reply.disposition(reply))
    {:reply, reply}
  end

  defp handle_session_step({:hangup, session, reply, timeout, respondent}) do
    update_respondent(respondent, {:ok, session, timeout}, Reply.disposition(reply))
    :end
  end

  defp handle_session_step({:end, reply, respondent}) do
    update_respondent(respondent, :end, Reply.disposition(reply))

    case Reply.steps(reply) do
      [] ->
        :end
      _ ->
        {:end, {:reply, reply}}
    end
  end

  defp handle_session_step({:rejected, reply, respondent}) do
    update_respondent(respondent, :rejected)
    {:end, {:reply, reply}}
  end

  defp handle_session_step({:rejected, session, reply, timeout, respondent}) do
    update_respondent(respondent, {:rejected, session, timeout})
    {:reply, reply}
  end

  defp handle_session_step({:rejected, respondent}) do
    update_respondent(respondent, :rejected)
    :end
  end

  defp handle_session_step({:stalled, session, respondent}) do
    update_respondent(respondent, {:stalled, session})
  end

  defp handle_session_step({:stopped, reply, respondent}) do
    update_respondent(respondent, :stopped, Reply.disposition(reply))
    :end
  end

  defp handle_session_step({:failed, respondent}) do
    update_respondent(respondent, :failed)
    :end
  end

  defp match_condition(responses, bucket) do
    bucket_vars = Map.keys(bucket.condition)

    Enum.all?(bucket_vars, fn var ->
      Enum.any?(responses, fn res ->
        (res.field_name == var) &&
          res.value |> QuotaBucket.matches_condition?(Map.fetch!(bucket.condition, var))
      end)
    end)
  end

  defp update_respondent(respondent, :end) do
    update_respondent(respondent, :end, nil)
  end

  defp update_respondent(respondent, {:stalled, session}) do
    respondent
    |> Respondent.changeset(%{state: "stalled", session: Session.dump(session), timeout_at: nil})
    |> Repo.update!
  end

  defp update_respondent(respondent, :rejected) do
    respondent
    |> Respondent.changeset(%{state: "rejected", session: nil, timeout_at: nil})
    |> Repo.update!
  end

  defp update_respondent(respondent, {:rejected, session, timeout}) do
    respondent
      |> Respondent.changeset(%{state: "rejected", session: Session.dump(session), timeout_at: next_timeout(respondent, timeout)})
      |> Repo.update!
  end

  defp update_respondent(respondent, :failed) do
    session = respondent.session |> Session.load
    mode = session.current_mode |> SessionMode.mode
    old_disposition = respondent.disposition
    respondent
    |> Respondent.changeset(%{state: "failed", session: nil, timeout_at: nil, disposition: Flow.failed_disposition_from(respondent.disposition)})
    |> Repo.update!
    |> create_disposition_history(old_disposition, mode)
  end

  defp update_respondent(respondent, :stopped, disposition) do
    session = respondent.session |> Session.load
    update_respondent_and_set_disposition(respondent, session, nil, nil, nil, disposition, "failed")
  end

  defp update_respondent(respondent, {:ok, session, timeout}, nil) do
    effective_modes = respondent.effective_modes || []
    effective_modes =
      if session do
        mode = Ask.Runtime.SessionMode.mode(session.current_mode)
        Enum.uniq(effective_modes ++ [mode])
      else
        effective_modes
      end

    timeout_at = next_timeout(respondent, timeout)
    respondent
    |> Respondent.changeset(%{state: "active", session: Session.dump(session), timeout_at: timeout_at, language: session.flow.language, effective_modes: effective_modes})
    |> Repo.update!
  end

  defp update_respondent(respondent, {:ok, session, timeout}, disposition) do
    update_respondent_and_set_disposition(respondent, session, Session.dump(session), timeout, next_timeout(respondent, timeout), disposition, "active")
  end

  defp update_respondent(respondent, :end, reply_disposition) do
    old_disposition = respondent.disposition

    new_disposition =
      old_disposition
      |> Flow.resulting_disposition(reply_disposition)
      |> Flow.resulting_disposition("completed")

    mode =
      if respondent.session do
        session = respondent.session |> Session.load
        session.current_mode |> SessionMode.mode
      else
        nil
      end

    respondent
    |> Respondent.changeset(%{state: "completed", disposition: new_disposition, session: nil, completed_at: Timex.now, timeout_at: nil})
    |> Repo.update!
    |> create_disposition_history(old_disposition, mode)
    |> update_quota_bucket(old_disposition, respondent.session["count_partial_results"])
  end

  def update_respondent_disposition(session, disposition) do
    respondent = session.respondent
    old_disposition = respondent.disposition
    if Flow.should_update_disposition(old_disposition, disposition) do
      respondent = respondent
      |> Respondent.changeset(%{disposition: disposition})
      |> Repo.update!
      |> create_disposition_history(old_disposition, session.current_mode |> SessionMode.mode)

      %{session | respondent: respondent}
    else
      session
    end
  end

  defp update_respondent_and_set_disposition(respondent, session, dump, timeout, timeout_at, disposition, state) do
    old_disposition = respondent.disposition
    if Flow.should_update_disposition(old_disposition, disposition) do
      respondent
      |> Respondent.changeset(%{disposition: disposition, state: state, session: dump, timeout_at: timeout_at})
      |> Repo.update!
      |> create_disposition_history(old_disposition, session.current_mode |> SessionMode.mode)
      |> update_quota_bucket(old_disposition, session.count_partial_results)
    else
      update_respondent(respondent, {:ok, session, timeout}, nil)
    end
  end

  defp next_timeout(respondent, timeout) do
    timeout_at = Timex.shift(Timex.now, minutes: timeout)
    (respondent |> Repo.preload(:survey)).survey
    |> Survey.next_available_date_time(timeout_at)
  end

  defp create_disposition_history(respondent, old_disposition, mode) do
    if respondent.disposition && respondent.disposition != old_disposition do
      %RespondentDispositionHistory{
        respondent: respondent,
        disposition: respondent.disposition,
        mode: mode}
      |> Repo.insert!
    end
    respondent
  end

  defp update_quota_bucket(respondent, old_disposition, count_partial_results) do
    if should_update_quota_bucket(respondent.disposition, old_disposition, count_partial_results) do
      responses = respondent |> assoc(:responses) |> Repo.all
      matching_bucket = Repo.all(from b in QuotaBucket, where: b.survey_id == ^respondent.survey_id)
                      |> Enum.find( fn bucket -> match_condition(responses, bucket) end )

      if matching_bucket do
        from(q in QuotaBucket, where: q.id == ^matching_bucket.id) |> Ask.Repo.update_all(inc: [count: 1])
      end
    end
    respondent
  end

  defp should_update_quota_bucket(new_disposition, old_disposition, true) do
    (new_disposition != old_disposition && new_disposition == "interim partial")
    || (new_disposition == "completed" && old_disposition != "interim partial" && old_disposition != "completed")
  end

  defp should_update_quota_bucket(new_disposition, old_disposition, _) do
    new_disposition != old_disposition && new_disposition == "completed"
  end

  # Estimates the amount of respondents the broker will have to initiate contact with
  # to get the completed respondents needed.
  defp batch_size(survey, respondents_by_state) do
    case completed_respondents_needed_by(survey) do
      :all ->
        default_batch_size()

      respondents_target when is_integer(respondents_target) ->
        successful = successful_respondents(survey, respondents_by_state)
        estimated_success_rate = estimated_success_rate(successful, respondents_by_state, respondents_target)
        (respondents_target - successful) / estimated_success_rate
        |> trunc
    end
  end

  defp default_batch_size do
    Survey.environment_variable_named(:batch_size)
  end

  defp batch_limit_per_minute do
    Survey.environment_variable_named(:batch_limit_per_minute)
  end

  defp estimated_success_rate(successful, respondents_by_state, respondents_target) do
    current_success_rate = success_rate(successful, respondents_by_state["completed"], respondents_by_state["failed"], respondents_by_state["rejected"])
    completion_rate = current_completion_rate(successful, respondents_target)
    %{:valid_respondent_rate => initial_valid_respondent_rate,
      :eligibility_rate => initial_eligibility_rate,
      :response_rate => initial_response_rate } = Survey.config_rates()

    initial_success_rate = initial_valid_respondent_rate * initial_eligibility_rate * initial_response_rate
    (1 - completion_rate) * initial_success_rate + completion_rate * current_success_rate
  end

  defp success_rate(_, 0, 0, 0), do: 1
  defp success_rate(successful, completed_respondents, failed_respondents, rejected_respondents) do
    successful / (completed_respondents + failed_respondents + rejected_respondents)
  end

  defp current_completion_rate(_, respondents_target) when is_nil(respondents_target), do: 0
  defp current_completion_rate(completed, respondents_target), do: completed / respondents_target

  defp successful_respondents(survey, respondents_by_state) do
    quota_completed = Repo.one(
      from q in (survey |> assoc(:quota_buckets)),
      select: fragment("sum(least(count, quota))")
    )

    case quota_completed do
      nil -> respondents_by_state["completed"]
      value -> value |> Decimal.to_integer
    end
  end

  defp completed_respondents_needed_by(survey) do
    survey_id = survey.id
    quota_target = Repo.one(from q in QuotaBucket,
                      where: q.survey_id == ^survey_id,
                      select: sum(q.quota))
    cutoff_target = survey.cutoff
    targets_compacted = [quota_target, cutoff_target] |> Enum.reject(&is_nil/1)

    if targets_compacted |> Enum.empty? do
      :all
    else
      res = targets_compacted
            |> Enum.max()
            |> Decimal.new()
            |> Decimal.to_integer()
      res
    end
  end
end
