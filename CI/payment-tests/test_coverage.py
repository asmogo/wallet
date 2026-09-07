import tempfile
import unittest
from pathlib import Path
from check_coverage import android_results, missing_tests


class CoverageGateTests(unittest.TestCase):
    def test_missing_skipped_and_failed_are_not_coverage(self):
        manifest = {'android': {'pr': ['Payments/a', 'Payments/b'], 'full': ['Payments/c']}}
        self.assertEqual(missing_tests(manifest, 'android', 'pr', {}), ['Payments/a', 'Payments/b'])
        self.assertEqual(missing_tests(manifest, 'android', 'pr', {'Payments/a': [True], 'Payments/b': [False]}), ['Payments/b'])
        self.assertEqual(missing_tests(manifest, 'android', 'full', {'Payments/a': [True], 'Payments/b': [True]}), ['Payments/c'])
        self.assertEqual(missing_tests(manifest, 'android', 'pr', {'Payments/a': [True], 'Payments/b': [True]}), [])

    def test_junit_skip_failure_and_mixed_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'TEST-payments.xml').write_text('''<testsuite>
              <testcase classname="app.Payments" name="paid"/>
              <testcase classname="app.Payments" name="skipped"><skipped/></testcase>
              <testcase classname="app.Payments" name="retry"><failure/></testcase>
              <testcase classname="app.Payments" name="retry"/>
            </testsuite>''')
            self.assertEqual(android_results(directory), {
                'Payments/paid': [True], 'Payments/skipped': [False], 'Payments/retry': [False, True]})
