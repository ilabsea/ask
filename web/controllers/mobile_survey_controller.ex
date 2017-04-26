defmodule Ask.MobileSurveyController do
  alias Ask.Runtime.{Broker, Reply}
  alias Ask.Respondent
  use Ask.Web, :controller

  def index(conn, %{"respondent_id" => respondent_id, "token" => token}) do
    authorize(conn, respondent_id, token, fn ->
      do_index(conn, respondent_id, token)
    end)
  end

  defp do_index(conn, respondent_id, token) do
    respondent = Repo.get!(Respondent, respondent_id)
    cookie_name = Respondent.mobile_web_cookie_name(respondent_id)
    respondent_cookie = respondent.mobile_web_cookie_code
    if respondent_cookie do
      request_cookie = fetch_cookies(conn).req_cookies[cookie_name]
      if request_cookie == respondent_cookie do
        render_index(conn, respondent_id, token)
      else
        raise Ask.UnauthorizedError, conn: conn
      end
    else
      cookie_value = Ecto.UUID.generate

      respondent
      |> Respondent.changeset(%{mobile_web_cookie_code: cookie_value})
      |> Repo.update!

      conn
      |> put_resp_cookie(cookie_name, cookie_value)
      |> render_index(respondent_id, token)
    end
  end

  defp render_index(conn, respondent_id, token) do
    conn
    |> put_layout({Ask.LayoutView, "mobile_survey.html"})
    |> render("index.html", respondent_id: respondent_id, token: token)
  end

  def get_step(conn, %{"respondent_id" => respondent_id, "token" => token}) do
    authorize(conn, respondent_id, token, fn ->
      sync_step(conn, respondent_id, :answer)
    end)
  end

  def send_reply(conn, %{"respondent_id" => respondent_id, "token" => token, "value" => value, "step_id" => step_id}) do
    authorize(conn, respondent_id, token, fn ->
      sync_step(conn, respondent_id, {:reply_with_step_id, value, step_id})
    end)
  end

  defp sync_step(conn, respondent_id, value) do
    respondent = Repo.get!(Respondent, respondent_id)
    survey = Repo.preload(respondent, :survey).survey

    {step, progress, error_msg} =
      cond do
        survey.state in ["completed", "cancelled"] ->
          questionnaires = Repo.preload(survey, :questionnaires).questionnaires
          questionnaire = Enum.random(questionnaires)
          msg = questionnaire.mobile_web_survey_is_over_message || "The survey is over"
          {end_step(msg), end_progress(), nil}
        respondent.state in ["pending", "active", "stalled"] ->
          case Broker.sync_step(respondent, value) do
            {:reply, reply} ->
              {first_step(reply), progress(reply), reply.error_msg}
            {:end, {:reply, reply}} ->
              {first_step(reply), progress(reply), reply.error_msg}
            :end ->
              {end_step(), end_progress(), nil}
          end
        true ->
          {end_step(), end_progress(), nil}
      end

    render(conn, "show_step.json", step: step, progress: progress, error_message: error_msg)
  end

  defp first_step(reply) do
    reply |> Reply.steps() |> hd
  end

  defp progress(reply) do
    if reply.current_step && reply.total_steps && reply.total_steps > 0 do
      100 * (reply.current_step / reply.total_steps)
    else
      0.0
    end
  end

  defp end_step(msg \\ "The survey has ended") do
    %{
      type: "end",
      prompts: [msg],
      title: msg,
    }
  end

  defp end_progress do
    100.0
  end

  defp authorize(conn, respondent_id, token, success_fn) do
    if Respondent.token(respondent_id) == token do
      success_fn.()
    else
      raise Ask.UnauthorizedError, conn: conn
    end
  end
end
