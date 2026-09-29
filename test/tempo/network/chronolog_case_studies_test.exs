defmodule Tempo.Network.ChronoLogCaseStudiesTest do
  use ExUnit.Case, async: true

  # Validation of Tempo.Network against real ChronoLog models. Each
  # `.clog` file under test/support/data/chronolog/ is a published
  # chronological network exported by ChronoLog 3 (Levy et al. 2020),
  # decoded by `Tempo.Network.ChronoLog` and re-solved by Tempo. The
  # files come from:
  #
  #   * the Egyptian 26th dynasty worked example (the same chronology
  #     the hand-built `Tempo.Network.EgyptianDynastyTest` models);
  #
  #   * three models from the 2022 "Radiocarbon Dating and Chronology
  #     of the Ancient Near East" (RDC) workshop — Dynasty 18, the
  #     Aegean LH→PG ceramic sequence, and the Iron Age Levant; and
  #
  #   * the Mediterranean Late Bronze Age case study from Levy et al.'s
  #     final paper.
  #
  # The RDC models are purely *relative* chronologies (their absolute
  # dates would come from radiocarbon/OxCal, which the network layer
  # does not compute), so they are validated by consistency and by the
  # qualitative constraints biting; the Egyptian and Mediterranean
  # models carry absolute anchors and are validated numerically.

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{ChronoLog, Solver, TimePeriod}

  @fixtures "test/support/data/chronolog"

  @case_studies %{
    "Egyptian-Dyn-26-CLOG3.clog" => %{periods: 14, sequences: 2, relations: 13},
    "RDC-2022-model-1-dyn-18-CLOG3.clog" => %{periods: 9, sequences: 1, relations: 2},
    "RDC-2022-model-2-Aegean-LH-to-PG-CLOG3.clog" => %{periods: 20, sequences: 4, relations: 13},
    "RDC-2022-model-3-IronAge-Levant-CLOG3.clog" => %{periods: 25, sequences: 1, relations: 23},
    "case-study-mediterranean-LB-for-final-paper-CLOG3.clog" => %{
      periods: 13,
      sequences: 6,
      relations: 13
    }
  }

  defp load(file), do: ChronoLog.from_file(Path.join(@fixtures, file))

  defp bounds(period) do
    {
      TimePeriod.year(period.earliest_start),
      TimePeriod.year(period.latest_start),
      TimePeriod.year(period.earliest_end),
      TimePeriod.year(period.latest_end)
    }
  end

  describe "decoding and consistency" do
    test "every case study loads and is internally consistent" do
      for {file, _} <- @case_studies do
        assert Solver.consistent?(load(file)), "#{file} should be consistent"
      end
    end

    test "each model decodes the expected periods, sequences and relations" do
      for {file, expected} <- @case_studies do
        network = load(file)

        actual = %{
          periods: map_size(network.periods),
          sequences: length(network.sequences),
          relations: length(network.relations)
        }

        assert actual == expected, "#{file} structure mismatch"
      end
    end
  end

  describe "Egyptian 26th dynasty (Levy et al. Fig. 2a)" do
    setup do
      {:ok, tightened} = Solver.propagate(load("Egyptian-Dyn-26-CLOG3.clog"))
      %{network: tightened}
    end

    test "tightening the .clog reproduces the canonical reign dates", %{network: network} do
      reigns = [
        "Psammetichus I",
        "Necho II",
        "Psammetichus II",
        "Apries",
        "Amasis",
        "Psammetichus III"
      ]

      reign_spans =
        Map.new(reigns, fn name ->
          period = network.periods[name]
          {name, {TimePeriod.year(period.earliest_start), TimePeriod.year(period.earliest_end)}}
        end)

      # Anchored only by the Persian conquest (525 BCE) and the
      # epigraphic Apis-bull delays, the solver recovers exactly the
      # dates the hand-built EgyptianDynastyTest asserts.
      assert reign_spans == %{
               "Psammetichus I" => {-664, -610},
               "Necho II" => {-610, -595},
               "Psammetichus II" => {-595, -589},
               "Apries" => {-589, -570},
               "Amasis" => {-570, -526},
               "Psammetichus III" => {-526, -525}
             }
    end

    test "the recovered dates are exact, not merely bounded", %{network: network} do
      for name <- ["Psammetichus I", "Amasis", "Psammetichus III"] do
        period = network.periods[name]
        assert TimePeriod.year(period.earliest_start) == TimePeriod.year(period.latest_start)
        assert TimePeriod.year(period.earliest_end) == TimePeriod.year(period.latest_end)
      end
    end

    test "the Persian conquest event anchors the dynasty's end", %{network: network} do
      conquest = network.periods["Persian conquest of Egypt"]
      assert TimePeriod.year(conquest.earliest_start) == -525
      assert TimePeriod.year(conquest.latest_end) == -525
    end
  end

  describe "Mediterranean Late Bronze Age synchronisms" do
    setup do
      {:ok, tightened} =
        Solver.propagate(load("case-study-mediterranean-LB-for-final-paper-CLOG3.clog"))

      %{network: tightened}
    end

    test "Equality synchronisms bind the Helladic and Minoan phases identically",
         %{network: network} do
      # "LH III A1 Equality LM III A1" and the A2 pair force the Helladic
      # and Minoan phases to share both boundaries.
      assert bounds(network.periods["LH III A1"]) == bounds(network.periods["LM III A1"])
      assert bounds(network.periods["LH III A2"]) == bounds(network.periods["LM III A2"])
    end

    test "event date windows pin the Uluburun and Tel Batash anchors", %{network: network} do
      # Events decode to zero-duration periods sitting in their dateLB..dateUB window.
      assert bounds(network.periods["Uluburun shipwreck"]) == {-1340, -1289, -1340, -1289}
      assert bounds(network.periods["Batash VII - C14 sample"]) == {-1437, -1394, -1437, -1394}
    end
  end

  describe "Aegean LH→PG relative chronology (Included in)" do
    test "anchoring a ceramic phase confines the strata included in it" do
      # Megiddo K8/K7, Maroni and Shean VII are all "Included in" the
      # Late LH IIIB phase. Anchoring that phase to a window must place
      # each contained stratum inside it.
      {:ok, network} =
        load("RDC-2022-model-2-Aegean-LH-to-PG-CLOG3.clog")
        |> Network.add_period("Late LH IIIB", from: ~o"-1250Y", to: ~o"-1200Y")
        |> Solver.propagate()

      for stratum <- ["Megiddo K8", "Megiddo K7", "Maroni", "Shean VII"] do
        period = network.periods[stratum]
        assert TimePeriod.year(period.earliest_start) >= -1250, "#{stratum} starts before phase"
        assert TimePeriod.year(period.latest_end) <= -1200, "#{stratum} ends after phase"
      end
    end

    test "a stratum cannot be placed outside the phase that contains it" do
      # Megiddo K8 is "Included in" Late LH IIIB; asserting it falls
      # entirely before that phase contradicts the containment.
      network =
        load("RDC-2022-model-2-Aegean-LH-to-PG-CLOG3.clog")
        |> Network.add_relation(:before, "Megiddo K8", "Late LH IIIB")

      refute Solver.consistent?(network)
    end
  end

  describe "Dynasty 18 lone tomb (boundary inequalities)" do
    test "the Sennefer tomb's bracketing synchronisms are active constraints" do
      # The Sennefer tomb "Starts after or at start of" Tutankhamun and
      # "Ends before or at start of" Horemheb. Placing the tomb wholly
      # after Horemheb contradicts the second of these.
      network =
        load("RDC-2022-model-1-dyn-18-CLOG3.clog")
        |> Network.add_relation(:after, "Sennefer Tomb", "Horemheb")

      refute Solver.consistent?(network)
    end
  end
end
