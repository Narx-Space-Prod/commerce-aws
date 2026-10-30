import importlib.util
import unittest
from pathlib import Path


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / 'scripts' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


class DeliveryBoundaries(unittest.TestCase):
    def test_cart_does_not_rebuild_java(self):
        self.assertEqual(module('changes').select(['application/orders/cart/app.py']), ['cart'])

    def test_docs_do_not_build(self):
        self.assertEqual(module('changes').select(['DOC.md', 'application/frontend/README.md']), [])

    def test_workflow_changes_rebuild_all(self):
        self.assertEqual(len(module('changes').select(['.github/workflows/ci.yml'])), 4)

    def test_inventory_and_platform_changes_do_not_rebuild_images(self):
        self.assertEqual(module('changes').select(['scripts/inventory.py', 'scripts/platform.sh', 'deploy/platform/storage.yaml']), [])

    def test_release_rejects_mutable_foreign_or_missing_images(self):
        release = module('release')
        images = {name: f'123456789012.dkr.ecr.ap-south-1.amazonaws.com/commerce-aws/{name}@sha256:' + 'a' * 64 for name in release.COMPONENTS}
        doc = {'release': {'source': 'b' * 40, 'images': images}}
        release.validate(doc, '123456789012', 'ap-south-1')
        with self.assertRaises(ValueError):
            release.validate(doc, '999999999999', 'ap-south-1')
        images['cart'] = 'redis:latest'
        with self.assertRaises(ValueError):
            release.validate(doc)


if __name__ == '__main__':
    unittest.main()
