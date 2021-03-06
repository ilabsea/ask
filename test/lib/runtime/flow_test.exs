defmodule Ask.FlowTest do
  use ExUnit.Case
  use Ask.DummySteps
  import Ask.Factory
  import Ask.StepBuilder
  alias Ask.Runtime.{Flow, Reply, ReplyHelper}
  alias Ask.Runtime.Flow.TextVisitor
  require Ask.Runtime.ReplyHelper

  @quiz build(:questionnaire, steps: @dummy_steps)
  @sms_visitor TextVisitor.new("sms")
  @ivr_visitor TextVisitor.new("ivr")

  test "start" do
    flow = Flow.start(@quiz, "sms")
    assert %Flow{language: "en"} = flow
  end

  @languageStep %{
    "id" => "1234-5678",
    "type" => "language-selection",
    "title" => "Language selection",
    "store" => "",
    "prompt" => %{
      "sms" => "1 for English, 2 for Spanish",
      "ivr" => %{
        "text" => "1 para ingles, 2 para español",
        "audioSource" => "tts",
      }
    },
    "language_choices" => ["en", "es"],
  }

  test "first step of empty quiz" do
    quiz = build(:questionnaire)
    step = Flow.start(quiz, "sms") |> Flow.step(@sms_visitor)
    assert {:end, _, _} = step
  end

  test "first step (sms mode)" do
    step = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == nil # becuase of sms mode
    assert ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO") = reply
  end

  test "first step (ivr mode)" do
    step = Flow.start(@quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == 1
    assert ReplyHelper.simple("Do you smoke?", %{"text" => "Do you smoke? Press 8 for YES, 9 for NO", "audio_source" => "tts"}) = reply
  end

  test "first step (ivr mode) with multiple choice for num digits, different lengths" do
    steps = [
      multiple_choice_step(
        id: Ecto.UUID.generate,
        title: "Do you smoke?",
        prompt: prompt(
          sms: sms_prompt("Do you smoke? Reply 1 for YES, 2 for NO"),
          ivr: tts_prompt("Do you smoke? Press 8 for YES, 9 for NO")
        ),
        store: "Smokes",
        choices: [
          choice(value: "Yes", responses: responses(sms: ["Yes", "Y", "1"], ivr: ["8, 123, 45"])),
          choice(value: "No", responses: responses(sms: ["No", "N", "2"], ivr: ["9, 67, #, 6789"]))
        ]
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == nil
  end

  test "first step (ivr mode) with multiple choice for num digits, all same length" do
    steps = [
      multiple_choice_step(
        id: Ecto.UUID.generate,
        title: "Do you smoke?",
        prompt: prompt(
          sms: sms_prompt("Do you smoke? Reply 1 for YES, 2 for NO"),
          ivr: tts_prompt("Do you smoke? Press 8 for YES, 9 for NO")
        ),
        store: "Smokes",
        choices: [
          choice(value: "Yes", responses: responses(sms: ["Yes", "Y", "1"], ivr: ["8, 7, 6"])),
          choice(value: "No", responses: responses(sms: ["No", "N", "2"], ivr: ["9, 1, #, 2"]))
        ]
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == 1
  end

  test "first step (ivr mode) with language selection for num digits" do
    steps = [
      language_selection_step(
        id: Ecto.UUID.generate,
        title: "Do you smoke?",
        prompt: %{
          "sms" => sms_prompt("Do you smoke? Reply 1 for YES, 2 for NO"),
          "ivr" => tts_prompt("Do you smoke? Press 8 for YES, 9 for NO")
        },
        store: "Smokes",
        choices: ["en", "es"]
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == 1
  end

  test "first step (ivr mode) with language selection for num digits, too many languages" do
    steps = [
      language_selection_step(
        id: Ecto.UUID.generate,
        title: "Do you smoke?",
        prompt: %{
          "sms" => sms_prompt("Do you smoke? Reply 1 for YES, 2 for NO"),
          "ivr" => tts_prompt("Do you smoke? Press 8 for YES, 9 for NO")
        },
        store: "Smokes",
        choices: ["en", "es", "a", "b", "c", "d", "e", "f", "g", "h"]
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == nil
  end

  test "first step (ivr mode) with numeric, no min/max, for num digits" do
    steps = [
      numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(
          sms: sms_prompt("Which is the second perfect number??"),
          ivr: tts_prompt("Which is the second perfect number")
          ),
        store: "Perfect Number",
        skip_logic: default_numeric_skip_logic(),
        alphabetical_answers: false,
        refusal: nil
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == nil
  end

  test "first step (ivr mode) with numeric, with max and min, for num digits, different lengths" do
    steps = [
      numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(
          sms: sms_prompt("Which is the second perfect number??"),
          ivr: tts_prompt("Which is the second perfect number")
          ),
        store: "Perfect Number",
        skip_logic: numeric_skip_logic(min_value: 0, max_value: 12345, ranges_delimiters: "25,75", ranges: []),
        alphabetical_answers: false,
        refusal: nil,
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == nil
  end

  test "first step (ivr mode) with numeric, with max and min, for num digits, same lengths" do
    steps = [
      numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(
          sms: sms_prompt("Which is the second perfect number??"),
          ivr: tts_prompt("Which is the second perfect number")
          ),
        store: "Perfect Number",
        skip_logic: numeric_skip_logic(min_value: 12345, max_value: 56789, ranges_delimiters: "25,75", ranges: []),
        alphabetical_answers: false,
        refusal: nil,
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == 5
  end

  test "first step (ivr mode) with numeric, with max and min, for num digits, same lengths but refusal different length" do
    steps = [
      numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(
          sms: sms_prompt("Which is the second perfect number??"),
          ivr: tts_prompt("Which is the second perfect number")
          ),
        store: "Perfect Number",
        skip_logic: numeric_skip_logic(min_value: 12345, max_value: 56789, ranges_delimiters: "25,75", ranges: []),
        alphabetical_answers: false,
        refusal: %{
          "responses" => %{
            "ivr" => ["#", "12"]
          }
        },
      )]
    quiz = build(:questionnaire, steps: steps)
    step = Flow.start(quiz, "ivr") |> Flow.step(@ivr_visitor)
    assert {:ok, %Flow{}, reply} = step
    assert Reply.num_digits(reply) == nil
  end

  test "retry step" do
    {:ok, flow, _prompts} = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    {:ok, %Flow{}, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")} = flow |> Flow.retry(@sms_visitor)
  end

  test "replies when never started" do
    # this can happen on a fallback channel
    step = Flow.start(@quiz, "sms")
    |> Flow.step(@sms_visitor, Flow.Message.reply("Y"))
    assert {:ok, %Flow{}, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO", %{"Smokes" => "Yes"})} = step
  end

  test "next step with store" do
    {:ok, flow, _} = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("Y"))
    assert {:ok, %Flow{}, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO", %{"Smokes" => "Yes"})} = step
  end

  test "next step (ivr mode)" do
    {:ok, flow, _} = Flow.start(@quiz, "ivr") |> Flow.step(@ivr_visitor)
    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("8"))
    assert {:ok, %Flow{}, ReplyHelper.simple("Do you exercise", %{"text" => "Do you exercise? Press 1 for YES, 2 for NO", "audio_source" => "tts"}, %{"Smokes" => "Yes"})} = step
  end

  test "next step with STOP" do
    {:ok, flow, _} = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("StoP"))

    assert {:stopped, nil, reply} = step

    prompts = Reply.prompts(reply)
    disposition = Reply.disposition(reply)

    assert prompts == []
    assert disposition == "refused"
  end

  test "retry step (sms mode)" do
    {:ok, flow, _} = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("x"))
    assert {:ok, %Flow{}, reply} = step
    prompts = Reply.prompts(reply)
    assert prompts == [
      "You have entered an invalid answer",
      "Do you smoke? Reply 1 for YES, 2 for NO"]
  end

  test "retry step (ivr mode)" do
    {:ok, flow, _} = Flow.start(@quiz, "ivr") |> Flow.step(@ivr_visitor)
    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("0"))
    assert {:ok, %Flow{}, reply} = step
    prompts = Reply.prompts(reply)
    assert prompts == [
      %{"text" => "You have entered an invalid answer (ivr)", "audio_source" => "tts"},
      %{"text" => "Do you smoke? Press 8 for YES, 9 for NO", "audio_source" => "tts"}]
  end

  test "retry step up to 3 times (sms mode)" do
    {:ok, flow, _} = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("x"))
    {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert flow.retries == 1
    assert prompts == [
      "You have entered an invalid answer",
      "Do you smoke? Reply 1 for YES, 2 for NO"
    ]

    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("x"))
    {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert flow.retries == 2
    assert prompts == [
      "You have entered an invalid answer",
      "Do you smoke? Reply 1 for YES, 2 for NO"
    ]

    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("x"))

    assert {:no_retries_left, _, _} = step
  end

  test "retry step 2 times, then valid answer, then retry 3 times (ivr mode)" do
    {:ok, flow, _} = Flow.start(@quiz, "ivr") |> Flow.step(@ivr_visitor)
    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("0"))

    assert {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert flow.retries == 1
    assert prompts == [
      %{"text" => "You have entered an invalid answer (ivr)", "audio_source" => "tts"},
      %{"text" => "Do you smoke? Press 8 for YES, 9 for NO", "audio_source" => "tts"}
    ]

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("8"))

    assert {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)
    stores = Reply.stores(reply)

    assert flow.retries == 0
    assert stores == %{"Smokes" => "Yes"}
    assert prompts == [%{"text" => "Do you exercise? Press 1 for YES, 2 for NO", "audio_source" => "tts"}]

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("8"))

    assert {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert flow.retries == 1
    assert prompts == [
      %{"text" => "You have entered an invalid answer (ivr)", "audio_source" => "tts"},
      %{"text" => "Do you exercise? Press 1 for YES, 2 for NO", "audio_source" => "tts"}
    ]

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("8"))

    assert {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert flow.retries == 2
    assert prompts == [
      %{"text" => "You have entered an invalid answer (ivr)", "audio_source" => "tts"},
      %{"text" => "Do you exercise? Press 1 for YES, 2 for NO", "audio_source" => "tts"}
    ]

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.reply("8"))

    assert {:no_retries_left, _, _} = step
  end

  test "mark as failed when no reply is received after 3 retries (ivr)" do
    {:ok, flow, _} = Flow.start(@quiz, "ivr") |> Flow.step(@ivr_visitor)

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.no_reply)

    assert {:ok, flow, reply} = step
    assert flow.retries == 1
    assert ReplyHelper.simple("Do you smoke?", %{"text" => "Do you smoke? Press 8 for YES, 9 for NO", "audio_source" => "tts"}) = reply

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.no_reply)

    assert {:ok, flow, reply} = step
    assert flow.retries == 2
    assert ReplyHelper.simple("Do you smoke?", %{"text" => "Do you smoke? Press 8 for YES, 9 for NO", "audio_source" => "tts"}) = reply

    step = flow |> Flow.step(@ivr_visitor, Flow.Message.no_reply)

    assert {:no_retries_left, _, _} = step
  end

  test "retry question without the error message when no reply is received" do
    {:ok, flow, _} = Flow.start(@quiz, "ivr") |> Flow.step(@ivr_visitor)
    step = flow |> Flow.step(@ivr_visitor, Flow.Message.no_reply)

    assert {:ok, %Flow{retries: 1}, ReplyHelper.simple("Do you smoke?", %{"text" => "Do you smoke? Press 8 for YES, 9 for NO", "audio_source" => "tts"})} = step
  end

  test "next step with store, case insensitive, strip space" do
    {:ok, flow, _} = Flow.start(@quiz, "sms") |> Flow.step(@sms_visitor)
    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" y "))
    assert {:ok, %Flow{}, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO", %{"Smokes" => "Yes"})} = step
  end

  test "last step" do
    flow = Flow.start(@quiz, "sms")
    {:ok, flow, _} = flow |> Flow.step(@sms_visitor)
    {:ok, flow, _} = flow |> Flow.step(@sms_visitor, Flow.Message.reply("Y"))
    {:ok, flow, _} = flow |> Flow.step(@sms_visitor, Flow.Message.reply("N"))
    {:ok, flow, _} = flow |> Flow.step(@sms_visitor, Flow.Message.reply("99"))
    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("11"))
    assert {:end, _, _} = step
  end

  def init_quiz_and_send_response response do
    {:ok, flow, _} =
      build(:questionnaire, steps: @skip_logic)
      |> Flow.start("sms")
      |> Flow.step(@sms_visitor)
    flow |> Flow.step(@sms_visitor, Flow.Message.reply(response))
  end

  # skip logic
  test "when skip_logic is end it ends the flow" do
    result = init_quiz_and_send_response("Y")

    assert {:end, _, _} = result
  end

  test "when skip_logic is null it continues with next step" do
    result = init_quiz_and_send_response("N")

    assert {:ok, _, _} = result
  end

  test "when skip_logic is not present continues with next step" do
    result = init_quiz_and_send_response("M")

    assert {:ok, _, _} = result
  end

  test "when skip_logic is a valid id jumps to the specified id" do
    {:ok, flow, _} = init_quiz_and_send_response("S")

    assert flow.current_step == 3
  end

  # refusal skip logic
  test "when refusal skip_logic is end it ends the flow" do
    steps = [
      numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(sms: sms_prompt("Which is the second perfect number??")),
        store: "Perfect Number",
        skip_logic: default_numeric_skip_logic(),
        alphabetical_answers: false,
        refusal: %{
          "enabled" => true,
          "responses" => %{
            "sms" => %{
              "en" => ["skip"],
            }
          },
          "skip_logic" => "end",
        }
      ),
      multiple_choice_step(
        id: "aaa",
        title: "Title",
        prompt: %{
        },
        store: "Swims",
        choices: []
      ),
    ]

    {:ok, flow, _} =
      build(:questionnaire, steps: steps)
      |> Flow.start("sms")
      |> Flow.step(@sms_visitor)
    result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("skip"))

    assert {:end, _, %{stores: %{"Perfect Number" => "REFUSED"}}} = result
  end

  test "refusal is stronger than response" do
    steps = [
      numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(sms: sms_prompt("Which is the second perfect number??")),
        store: "Perfect Number",
        skip_logic: default_numeric_skip_logic(),
        alphabetical_answers: false,
        refusal: %{
          "enabled" => true,
          "responses" => %{
            "sms" => %{
              "en" => ["1"],
            }
          },
          "skip_logic" => "end",
        }
      ),
      multiple_choice_step(
        id: "aaa",
        title: "Title",
        prompt: %{
        },
        store: "Swims",
        choices: []
      ),
    ]

    {:ok, flow, _} =
      build(:questionnaire, steps: steps)
      |> Flow.start("sms")
      |> Flow.step(@sms_visitor)
    result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("1"))

    # No stores (because of refusal)
    assert {:end, _, %{stores: %{"Perfect Number" => "REFUSED"}}} = result
  end

  describe "numeric steps" do
    test "when value is in a middle range it finds it" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("50"))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "50"}}} = result
    end

    test "when value is in a middle range it finds it, permissive" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" 50 units "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "50"}}} = result
    end

    test "accepts a string as an answer" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" fifty "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "50"}}} = result
    end

    test "accepts a string with two words as an answer" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" fifty one "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "51"}}} = result
    end

    test "accepts a string close enough to a number as an answer" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" finty "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "50"}}} = result
    end

    test "accepts a string close enough to a number as an answer 2" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" fifti "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "50"}}} = result
    end

    test "accepts a string with two words that is close enough as an answer (2 errors)" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" finty onw "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "51"}}} = result
    end

    test "accepts a string with two words that is close enough to the same value more than one time" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" twenty_one "))
      assert {:end, _, %Ask.Runtime.Reply{stores: %{"Probability" => "21"}}} = result
    end

    test "does not accept a string when is close enough to more than one number as an answer" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" fixty "))

      assert {:ok, flow, reply} = result
      prompts = Reply.prompts(reply)

      assert flow.retries == 1
      assert prompts == [
        "You have entered an invalid answer",
        "What is the probability that a number has more prime factors than the sum of its digits?"
      ]
    end

    test "does not accept a string when is close enough to more than one number as an answer (2)" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" fixty three"))

      assert {:ok, flow, reply} = result
      prompts = Reply.prompts(reply)

      assert flow.retries == 1
      assert prompts == [
        "You have entered an invalid answer",
        "What is the probability that a number has more prime factors than the sum of its digits?"
      ]
    end

    test "does not accept a string when is not close enough to a number as an answer" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply(" finte "))

      assert {:ok, flow, reply} = result
      prompts = Reply.prompts(reply)

      assert flow.retries == 1
      assert prompts == [
        "You have entered an invalid answer",
        "What is the probability that a number has more prime factors than the sum of its digits?"
      ]
    end

    test "does not match a string when alphabetical_answers is set to false" do
      steps = [
        numeric_step(
          id: Ecto.UUID.generate,
          title: "Which is the second perfect number?",
          prompt: prompt(sms: sms_prompt("Which is the second perfect number?")),
          store: "Perfect Number",
          skip_logic: default_numeric_skip_logic(),
          alphabetical_answers: false,
          refusal: %{
            "enabled" => false
          }
        ),
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
          },
          store: "Swims",
          choices: []
        ),
      ]

      {:ok, flow, _} =
        build(:questionnaire, steps: steps)
        |> Flow.start("sms")
        |> Flow.step(@sms_visitor)
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("twenty-eight"))

      assert {:ok, flow, reply} = result

      prompts = Reply.prompts(reply)

      assert flow.retries == 1
      assert prompts == [
        "You have entered an invalid answer",
        "Which is the second perfect number?"
      ]
    end

    test "alphabetical answers works with a questionnaire with more than one language (es)" do
      steps = [numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(
          sms: sms_prompt("Which is the second perfect number??"),
          ivr: tts_prompt("Which is the second perfect number")
          ),
        store: "Perfect Number",
        skip_logic: default_numeric_skip_logic(),
        alphabetical_answers: true,
        refusal: nil
        )]

      languageStep = @languageStep
      steps = [languageStep | steps]
      quiz = build(:questionnaire, steps: steps)

      flow = Flow.start(quiz, "sms")
      assert flow.language == "en"

      step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("2"))
      {_, flow1, reply1} = step
      prompts = Reply.prompts(reply1)

      assert flow1.language == "es"
      assert prompts == ["Which is the second perfect number?? (Spanish)"]

      step2 = flow1 |> Flow.step(@sms_visitor, Flow.Message.reply("veintiocho"))

      {_, _, %Ask.Runtime.Reply{stores: %{"Perfect Number" => "28"}}} = step2
    end

    test "alphabetical answers works with a questionnaire with more than one language (en)" do
      steps = [numeric_step(
        id: Ecto.UUID.generate,
        title: "Which is the second perfect number?",
        prompt: prompt(
          sms: sms_prompt("Which is the second perfect number??"),
          ivr: tts_prompt("Which is the second perfect number")
          ),
        store: "Perfect Number",
        skip_logic: default_numeric_skip_logic(),
        alphabetical_answers: true,
        refusal: nil
        )]

      languageStep = @languageStep
      steps = [languageStep | steps]
      quiz = build(:questionnaire, steps: steps)

      flow = Flow.start(quiz, "sms")
      assert flow.language == "en"

      step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("1"))
      {_, flow1, reply1} = step
      prompts = Reply.prompts(reply1)

      assert flow1.language == "en"
      assert prompts == ["Which is the second perfect number??"]

      step2 = flow1 |> Flow.step(@sms_visitor, Flow.Message.reply("twenty-eight"))

      {_, _, %Ask.Runtime.Reply{stores: %{"Perfect Number" => "28"}}} = step2
    end

    @numeric_steps_no_min_max [
      numeric_step(
        id: "ddd",
        title:
        "What is the probability that a number has more prime factors than the sum of its digits?",
        prompt: prompt(
          sms: sms_prompt("What is the probability that a number has more prime factors than the sum of its digits?")
        ),
        store: "Probability",
        skip_logic: numeric_skip_logic(min_value: nil, max_value: nil,
          ranges_delimiters: "25,75", ranges: [
            %{
              "from" => nil,
              "to" => 24,
              "skip_logic" => "end"
            },
            %{
              "from" => 25,
              "to" => 74,
              "skip_logic" => "end"
            },
            %{
              "from" => 75,
              "to" => nil,
              "skip_logic" => "end"
            }
          ]
        ),
        alphabetical_answers: false,
        refusal: nil
      ),
    ]

    test "when value is in the first range and it has no min value it finds it" do
      {:ok, flow, _} =
        build(:questionnaire, steps: @numeric_steps_no_min_max)
        |> Flow.start("sms")
        |> Flow.step(@sms_visitor)
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("-10"))
      assert {:end, _, _} = result
    end

    test "when value is in the last range and it has no max value it finds it" do
      {:ok, flow, _} =
        build(:questionnaire, steps: @numeric_steps_no_min_max)
        |> Flow.start("sms")
        |> Flow.step(@sms_visitor)
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("999"))
      assert {:end, _, _} = result
    end

    test "when value is less than min" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("-1"))

      assert {:ok, %Flow{}, reply} = result
      prompts = Reply.prompts(reply)

      assert prompts == [
        "You have entered an invalid answer",
        "What is the probability that a number has more prime factors than the sum of its digits?"
      ]
    end

    test "when value is greater than max" do
      {:ok, flow, _} = init_quiz_and_send_response("S")
      result = flow |> Flow.step(@sms_visitor, Flow.Message.reply("101"))

      assert {:ok, %Flow{}, reply} = result
      prompts = Reply.prompts(reply)

      assert prompts == [
        "You have entered an invalid answer",
        "What is the probability that a number has more prime factors than the sum of its digits?"
      ]
    end
  end

  describe "when skip_logic is an invalid id" do
    test "when it doesn't exist raises" do
      assert_raise RuntimeError, fn ->
        init_quiz_and_send_response("A")
      end
    end

    test "when the step is previous raises" do
      {:ok, flow, _} = init_quiz_and_send_response("M")

      assert_raise RuntimeError, fn ->
        flow
        |> Flow.step(@sms_visitor, Flow.Message.reply("Y"))
      end
    end
  end

  test "language selection step" do
    steps = @dummy_steps
    languageStep = @languageStep
    steps = [languageStep | steps]
    quiz = build(:questionnaire, steps: steps)

    flow = Flow.start(quiz, "sms")
    assert flow.language == "en"

    step = flow |> Flow.step(@sms_visitor)
    assert {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert prompts == ["1 for English, 2 for Spanish"]

    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("2"))
    assert {:ok, flow, reply} = step
    prompts = Reply.prompts(reply)

    assert flow.language == "es"
    assert prompts == ["Do you smoke? Reply 1 for YES, 2 for NO (Spanish)"]
  end

  test "language selection step doesn't crash on non-numeric" do
    steps = @dummy_steps
    languageStep = @languageStep
    steps = [languageStep | steps]
    quiz = build(:questionnaire, steps: steps)

    flow = Flow.start(quiz, "sms")

    step = flow |> Flow.step(@sms_visitor)
    assert {:ok, flow, _} = step

    step = flow |> Flow.step(@sms_visitor, Flow.Message.reply("text"))
    assert {:ok, %Flow{}, reply} = step
    prompts = Reply.prompts(reply)
    assert prompts == [
      "You have entered an invalid answer",
      "1 for English, 2 for Spanish"]
  end

  test "first step (sms mode) with multiple messages separated by newline" do
    steps = [
      multiple_choice_step(
        id: Ecto.UUID.generate,
        title: "Do you smoke?",
        prompt: prompt(
          sms: sms_prompt("Do you smoke?\u{1E}Reply 1 for YES, 2 for NO"),
        ),
        store: "Smokes",
        choices: [
          choice(value: "Yes", responses: responses(sms: ["Yes", "Y", "1"], ivr: ["8"])),
          choice(value: "No", responses: responses(sms: ["No", "N", "2"], ivr: ["9"]))
        ]
      ),
    ]

    quiz = build(:questionnaire, steps: steps)

    step = Flow.start(quiz, "sms") |> Flow.step(@sms_visitor)
    assert {:ok, %Flow{}, reply} = step
    prompts = Reply.prompts(reply)
    assert prompts == ["Do you smoke?", "Reply 1 for YES, 2 for NO"]
  end

  describe "explanation steps" do
    test "adds previous explanation steps to prompts" do
      quiz = build(:questionnaire, steps: @explanation_steps_minimal)
      flow = Flow.start(quiz, "sms")
      flow_state = flow |> Flow.step(@sms_visitor)

      assert {:ok, flow, reply} = flow_state
      prompts = Reply.prompts(reply)

      assert prompts == ["Is this the last question?", "Do you exercise? Reply 1 for YES, 2 for NO"]
      assert flow.current_step == 1
    end

    test "ends but keeps the prompts" do
      quiz = build(:questionnaire, steps: @only_explanation_steps)
      flow = Flow.start(quiz, "sms")
      flow_state = flow |> Flow.step(@sms_visitor)

      assert {:end, _, reply} = flow_state
      prompts = Reply.prompts(reply)

      assert prompts == ["Is this the last question?", "Thanks for completing this survey"]
    end
  end

  describe "flag steps" do
    test "flag steps and send prompts" do
      quiz = build(:questionnaire, steps: @flag_steps)
      flow = Flow.start(quiz, "sms")
      flow_state = flow |> Flow.step(@sms_visitor)

      assert {:ok, flow, reply} = flow_state
      prompts = Reply.prompts(reply)
      disposition = Reply.disposition(reply)

      assert prompts == ["Do you exercise? Reply 1 for YES, 2 for NO"]
      assert disposition == "interim partial"
      assert flow.current_step == 1
    end

    test "ending keeps the last flag" do
      quiz = build(:questionnaire, steps: @partial_step)
      flow = Flow.start(quiz, "sms")
      flow_state = flow |> Flow.step(@sms_visitor)
      assert {:end, _, reply} = flow_state
      assert Reply.disposition(reply) == "interim partial"
    end

    test "two consecutive flag steps: ineligible, completed" do
      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Do you exercise?",
          prompt: prompt(
            sms: sms_prompt("Do you exercise? Reply 1 for YES, 2 for NO")
          ),
          store: "Exercises",
          choices: [
            choice(value: "Yes", responses: responses(sms: ["Yes", "Y", "1"], ivr: ["1"])),
            choice(value: "No", responses: responses(sms: ["No", "N", "2"], ivr: ["2"]))
          ]
        ),
        flag_step(
          id: "bbb",
          title: "b",
          disposition: "ineligible"
        ),
        flag_step(
          id: "ccc",
          title: "c",
          disposition: "completed"
        ),
      ]

      {:ok, flow, _} =
        build(:questionnaire, steps: steps)
        |> Flow.start("sms")
        |> Flow.step(@sms_visitor)
      assert {:end, _, reply} = flow |> Flow.step(@sms_visitor, Flow.Message.reply("1"))
      assert Reply.disposition(reply) == "ineligible"
    end

    test "two consecutive flag steps: refused, completed" do
      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Do you exercise?",
          prompt: prompt(
            sms: sms_prompt("Do you exercise? Reply 1 for YES, 2 for NO")
          ),
          store: "Exercises",
          choices: [
            choice(value: "Yes", responses: responses(sms: ["Yes", "Y", "1"], ivr: ["1"])),
            choice(value: "No", responses: responses(sms: ["No", "N", "2"], ivr: ["2"]))
          ]
        ),
        flag_step(
          id: "bbb",
          title: "b",
          disposition: "refused"
        ),
        flag_step(
          id: "ccc",
          title: "c",
          disposition: "completed"
        ),
      ]

      {:ok, flow, _} =
        build(:questionnaire, steps: steps)
        |> Flow.start("sms")
        |> Flow.step(@sms_visitor)
      assert {:end, _, reply} = flow |> Flow.step(@sms_visitor, Flow.Message.reply("1"))
      assert Reply.disposition(reply) == "refused"
    end
  end
end
