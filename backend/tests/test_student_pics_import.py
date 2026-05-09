import pathlib
import sys

sys.path.append(str(pathlib.Path(__file__).resolve().parents[2] / "database"))

from import_student_pics import parse_student_pics_csv, safe_name, transliterate_name  # noqa: E402


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def test_student_pics_csv_shape():
    records, stats = parse_student_pics_csv(REPO_ROOT / "StudentPicsDataset.csv")

    assert stats["raw_rows"] == 227
    assert stats["blank_rows"] == 100
    assert stats["photo_rows"] == 127
    assert stats["unique_students"] == 119
    assert stats["duplicate_photo_rows"] == 8
    assert len(records) == 119


def test_duplicate_student_ids_become_extra_photos():
    records, _ = parse_student_pics_csv(REPO_ROOT / "StudentPicsDataset.csv")
    by_id = {record.student_id: record for record in records}

    assert len(by_id["231004160"].photo_links) == 2
    assert by_id["231004160"].english_name == "Abdullah Mohamed Shatat"


def test_transliteration_and_safe_folder_name_are_ascii():
    english = transliterate_name("\u0645\u062d\u0645\u062f \u0639\u0644\u0627\u0621 \u0644\u0637\u0641\u0649")

    assert english == "Mohamed Alaa Lotfy"
    assert safe_name(english) == "Mohamed_Alaa_Lotfy"
