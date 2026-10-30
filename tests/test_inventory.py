import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('inventory', Path(__file__).parents[1] / 'scripts/inventory.py')
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class InventoryBoundaries(unittest.TestCase):
    def test_wrong_account_stops_before_resource_queries(self):
        with patch('sys.argv', ['inventory.py', '--profile', 'lab', '--account', '123456789012']), \
             patch.object(inventory, 'aws', return_value={'Account': '999999999999'}) as aws:
            with self.assertRaisesRegex(SystemExit, 'Account mismatch'):
                inventory.main()
        self.assertEqual(aws.call_count, 1)

    def test_denied_inventory_is_not_reported_as_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.json'
            args = ['inventory.py', '--profile', 'lab', '--account', '123456789012', '--output', str(path)]
            def aws(profile, region, operation):
                if operation[0] == 'sts':
                    return {'Account': '123456789012', 'Arn': 'arn:aws:iam::123456789012:role/lab'}
                raise RuntimeError('denied')
            with patch('sys.argv', args), patch.object(inventory, 'aws', side_effect=aws):
                self.assertEqual(inventory.main(), 2)
            self.assertFalse(json.loads(path.read_text())['complete'])


if __name__ == '__main__':
    unittest.main()
