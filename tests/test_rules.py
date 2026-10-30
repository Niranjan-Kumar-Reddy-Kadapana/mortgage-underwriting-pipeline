import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data_simulation"))
from generate_data import build, decide  # noqa: E402

BASE = dict(loan=240_000, value=300_000, income=10_000, debt=2_000, fico=720)


def d(**kw):
    return decide(**{**BASE, **kw})[0]


def test_ltv_boundary():
    assert d(loan=95_000, value=100_000) == "APPROVED"
    assert d(loan=95_010, value=100_000) == "DECLINED"


def test_dti_boundary():
    assert d(debt=4_300, fico=700) in ("APPROVED",)
    assert d(debt=4_301) == "DECLINED"


def test_fico_boundary():
    assert d(fico=619) == "DECLINED"
    assert d(fico=620) == "APPROVED"


def test_cosigner_band():
    assert d(fico=620, debt=3_600) == "REQUIRES_COSIGNER"
    assert d(fico=660, debt=4_300) == "REQUIRES_COSIGNER"
    assert d(fico=661, debt=4_300) == "APPROVED"
    assert d(fico=640, debt=3_599) == "APPROVED"


def test_multiple_reasons_are_ordered():
    status, reasons = decide(loan=99_000, value=100_000, income=10_000, debt=5_000, fico=600)
    assert status == "DECLINED" and len(reasons) == 3
    assert reasons[0] == "DECLINED_CREDIT_SCORE_BELOW_MIN"


def test_generator_is_deterministic():
    assert build(200, 1, 0)[3] == build(200, 1, 0)[3]


def test_no_real_ssn_range():
    _, credit, _, _ = build(300, 7, 0)
    assert all(r["ssn"].startswith("9") for r in credit)
