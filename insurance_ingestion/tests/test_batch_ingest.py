import unittest

from insurance_ingestion.batch_ingest import infer_category, infer_version


class BatchIngestionTests(unittest.TestCase):
    def test_categories_are_inferred_without_file_specific_ids(self) -> None:
        self.assertEqual(infer_category("JAKi summary Updated.pdf"), "jak_inhibitors")
        self.assertEqual(infer_category("Summary of GLP-1 R.A. for MASH.pdf"), "glp1_mash")
        self.assertEqual(infer_category("PPI Dx CODES.xlsb"), "ppi_coverage")

    def test_common_policy_date_formats_become_iso_versions(self) -> None:
        self.assertEqual(infer_version("Updated 25-06-2026.pdf"), "2026-06-25")
        self.assertEqual(infer_version("updated 2026-01-13.xlsb"), "2026-01-13")
        self.assertEqual(infer_version("Summary OLD.pdf"), "old")


if __name__ == "__main__":
    unittest.main()
