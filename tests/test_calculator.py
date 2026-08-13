import pytest
from metrics.calculator import calculate_metrics, SpeakerStats, ConversationMetrics


def test_single_speaker_full_duration():
    timeline = [("A", 0.0, 10.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    assert m.speaker_count == 1
    assert m.speakers[0].duration_sec == pytest.approx(10.0)
    assert m.speakers[0].percentage == pytest.approx(100.0)
    assert m.overlap_sec == pytest.approx(0.0)
    assert m.silence_sec == pytest.approx(0.0)


def test_two_equal_speakers_no_overlap():
    timeline = [("A", 0.0, 5.0), ("B", 5.0, 10.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    assert m.speaker_count == 2
    assert m.overlap_sec == pytest.approx(0.0)
    for s in m.speakers:
        assert s.duration_sec == pytest.approx(5.0)
        assert s.percentage == pytest.approx(50.0)


def test_overlap_is_detected():
    # A: 0-5, B: 3-8 → overlap 3-5 = 2s
    timeline = [("A", 0.0, 5.0), ("B", 3.0, 8.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    assert m.overlap_sec == pytest.approx(2.0)


def test_percentages_can_exceed_100_with_overlap():
    # A: 0-6 (60%), B: 4-10 (60%) → sum = 120%
    timeline = [("A", 0.0, 6.0), ("B", 4.0, 10.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    total_pct = sum(s.percentage for s in m.speakers)
    assert total_pct > 100.0


def test_silence_is_total_minus_speech():
    # Speech: 0-4, 7-10 → 7s speech, 3s silence
    timeline = [("A", 0.0, 4.0), ("B", 7.0, 10.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    assert m.speech_sec == pytest.approx(7.0)
    assert m.silence_sec == pytest.approx(3.0)


def test_silence_not_double_counted_when_speakers_overlap():
    # A: 0-6, B: 4-10 → union = 0-10 = 10s speech, 0s silence
    timeline = [("A", 0.0, 6.0), ("B", 4.0, 10.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    assert m.speech_sec == pytest.approx(10.0)
    assert m.silence_sec == pytest.approx(0.0)


def test_empty_timeline():
    m = calculate_metrics([], total_duration_sec=10.0)
    assert m.speaker_count == 0
    assert m.speakers == []
    assert m.speech_sec == pytest.approx(0.0)
    assert m.silence_sec == pytest.approx(10.0)
    assert m.overlap_sec == pytest.approx(0.0)


def test_speakers_sorted_by_duration_descending():
    timeline = [("A", 0.0, 2.0), ("B", 2.0, 9.0)]
    m = calculate_metrics(timeline, total_duration_sec=10.0)
    durations = [s.duration_sec for s in m.speakers]
    assert durations == sorted(durations, reverse=True)


def test_returns_correct_dataclass_types():
    m = calculate_metrics([("A", 0.0, 5.0)], total_duration_sec=10.0)
    assert isinstance(m, ConversationMetrics)
    assert isinstance(m.speakers[0], SpeakerStats)
