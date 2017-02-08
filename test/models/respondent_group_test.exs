defmodule Ask.RespondentGroupTest do
  use Ask.ModelCase

  alias Ask.{RespondentGroup, Channel}

  @valid_attrs %{name: "some content", sample: [], respondents_count: 0}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = RespondentGroup.changeset(%RespondentGroup{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = RespondentGroup.changeset(%RespondentGroup{}, @invalid_attrs)
    refute changeset.valid?
  end

  test "primary SMS and no fallback channel" do
    group = %RespondentGroup{channels: [%Channel{type: "ivr", name: "An IVR Channel"}, %Channel{type: "sms", name: "An SMS Channel"}]}

    prim = RespondentGroup.primary_channel(group, ["sms"])
    assert prim.name == "An SMS Channel"
    assert prim.type == "sms"

    fallback = RespondentGroup.fallback_channel(group, ["sms"])
    assert fallback == nil
  end

   test "primary IVR and no fallback channel" do
    group = %RespondentGroup{channels: [%Channel{type: "ivr", name: "An IVR Channel"}, %Channel{type: "sms", name: "An SMS Channel"}]}

    prim = RespondentGroup.primary_channel(group, ["ivr"])
    assert prim.name == "An IVR Channel"
    assert prim.type == "ivr"

    fallback = RespondentGroup.fallback_channel(group, ["ivr"])
    assert fallback == nil
  end

  test "primary SMS and fallback IVR channel" do
    group = %RespondentGroup{channels: [%Channel{type: "ivr", name: "An IVR Channel"}, %Channel{type: "sms", name: "An SMS Channel"}]}

    prim = RespondentGroup.primary_channel(group, ["sms", "ivr"])
    assert prim.name == "An SMS Channel"
    assert prim.type == "sms"

    fallback = RespondentGroup.fallback_channel(group, ["sms", "ivr"])
    assert fallback.name == "An IVR Channel"
    assert fallback.type == "ivr"
  end

  test "primary IVR and fallback SMS channel" do
    group = %RespondentGroup{channels: [%Channel{type: "ivr", name: "An IVR Channel"}, %Channel{type: "sms", name: "An SMS Channel"}]}

    prim = RespondentGroup.primary_channel(group, ["ivr", "sms"])
    assert prim.name == "An IVR Channel"
    assert prim.type == "ivr"

    fallback = RespondentGroup.fallback_channel(group, ["ivr", "sms"])
    assert fallback.name == "An SMS Channel"
    assert fallback.type == "sms"
  end
end
