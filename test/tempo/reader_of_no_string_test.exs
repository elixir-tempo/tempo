defmodule Tempo.ReaderOfNoStringTest do
  @moduledoc """
  What a reader is handed that is no string.

  A reader sits where what a caller was sent arrives: a field of a form, a
  parameter of a request, a value of a decoded document. One left empty is
  `nil`, and a number or a map comes as easily. Each reader raised a
  `FunctionClauseError` for it, where it returns an error for a string that
  is no date. It returns an error for this too, and its raising form raises
  that error.

  A string is read as it was: the empty one, and one far longer than any
  date, are an answer or an error and no raise.
  """
  use ExUnit.Case, async: true

  alias Tempo.Cron
  alias Tempo.CronError
  alias Tempo.ICal
  alias Tempo.JSCalendar
  alias Tempo.ParseError
  alias Tempo.RRule

  @no_strings [nil, :"", :a_date, 42, 1.5, %{}, %{"start" => "2026-06-15"}, [1, 2], {2026, 6, 15}]

  @iso8601_readers [
    {"Tempo.from_iso8601/1", &Tempo.from_iso8601/1},
    {"Tempo.parse/1", &Tempo.parse/1},
    {"Tempo.parse_date/1", &Tempo.parse_date/1},
    {"Tempo.parse_datetime/1", &Tempo.parse_datetime/1},
    {"Tempo.parse_time/1", &Tempo.parse_time/1},
    {"Tempo.parse_interval/1", &Tempo.parse_interval/1},
    {"Tempo.parse_duration/1", &Tempo.parse_duration/1}
  ]

  @iso8601_raising_readers [
    {"Tempo.from_iso8601!/1", &Tempo.from_iso8601!/1},
    {"Tempo.parse!/1", &Tempo.parse!/1},
    {"Tempo.parse_date!/1", &Tempo.parse_date!/1},
    {"Tempo.parse_datetime!/1", &Tempo.parse_datetime!/1},
    {"Tempo.parse_time!/1", &Tempo.parse_time!/1},
    {"Tempo.parse_interval!/1", &Tempo.parse_interval!/1},
    {"Tempo.parse_duration!/1", &Tempo.parse_duration!/1}
  ]

  @tagged_readers [
    {"Tempo.RRule.parse/1", &RRule.parse/1},
    {"Tempo.ICal.parse/1", &ICal.parse/1},
    {"Tempo.JSCalendar.parse/1", &JSCalendar.parse/1}
  ]

  describe "a reader of ISO 8601, handed what is no string" do
    test "returns a parse error that says so" do
      for {name, reader} <- @iso8601_readers, value <- @no_strings do
        assert {^name, ^value, {:error, %ParseError{} = error}} = {name, value, reader.(value)}
        assert Exception.message(error) =~ "it is not a string"
      end
    end

    test "returns it whatever calendar or options it is given" do
      for value <- @no_strings do
        assert {:error, %ParseError{}} = Tempo.from_iso8601(value, Calendrical.Hebrew)
        assert {:error, %ParseError{}} = Tempo.from_iso8601(value, strict: true)
        assert {:error, %ParseError{}} = Tempo.parse(value, locale: :en)
        assert {:error, %ParseError{}} = Tempo.parse_date(value, locale: :en)
      end
    end

    test "raises that error from its raising form" do
      for {name, reader} <- @iso8601_raising_readers, value <- @no_strings do
        error = assert_raise ParseError, fn -> reader.(value) end
        assert Exception.message(error) =~ "it is not a string", name
      end
    end

    test "names a value far too long to show by its start" do
      {:error, error} = Tempo.from_iso8601(Enum.to_list(1..10_000))

      assert String.length(Exception.message(error)) < 200
    end
  end

  describe "a reader of a cron expression, handed what is no string" do
    test "returns a cron error that says so" do
      for value <- @no_strings do
        assert {^value, {:error, %CronError{} = error}} = {value, Cron.parse(value)}
        assert Exception.message(error) =~ "A cron expression is a string"
        assert {:error, %CronError{}} = Cron.parse(value, from: Tempo.from_iso8601!("2026-06-15"))
      end
    end

    test "raises that error from its raising form" do
      for value <- @no_strings do
        assert_raise CronError, fn -> Cron.parse!(value) end
      end
    end
  end

  describe "a reader of a rule or of a calendar document, handed what is no string" do
    test "returns the value as no string" do
      for {name, reader} <- @tagged_readers, value <- @no_strings do
        assert {name, reader.(value)} == {name, {:error, {:not_a_string, value}}}
      end
    end

    test "raises an argument error from the rule's raising form" do
      for value <- @no_strings do
        assert_raise ArgumentError, ~r/not_a_string/, fn -> RRule.parse!(value) end
      end
    end
  end

  describe "a reader handed a string that is none of what it reads" do
    @strings ["", " ", "\0", String.duplicate("9", 5_000), String.duplicate("é", 2_000)]

    test "answers or returns an error, and does not raise" do
      readers = @iso8601_readers ++ @tagged_readers ++ [{"Tempo.Cron.parse/1", &Cron.parse/1}]

      for {name, reader} <- readers, string <- @strings do
        assert {^name, {tag, _answer}} = {name, reader.(string)}
        assert {name, tag} in [{name, :ok}, {name, :error}]
      end
    end
  end
end
