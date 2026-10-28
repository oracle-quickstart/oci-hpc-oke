"""Regression tests for opt-in compilation and stale dashboard removal."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import urlparse

PACKAGE = Path(__file__).resolve().parents[2] / 'terraform/files/grafana/jsonnet'
spec = importlib.util.spec_from_file_location('renderer', PACKAGE / 'render_dashboards.py')
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)
JSONNET = PACKAGE / '.cache/tools/go-jsonnet-0.21.0/jsonnet'


class KueueRendering(unittest.TestCase):
    def test_disabled_kueue_is_never_evaluated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            common = root / 'dashboards/common'
            common.mkdir(parents=True)
            (common / 'base.jsonnet').write_text('{uid: "base"}')
            (common / 'kueue.jsonnet').write_text('error "Kueue must not be evaluated"')
            output = root / 'build'
            result = renderer.compile_dashboards(root, output, JSONNET, root)
            self.assertEqual(set(result['common']), {'base.json'})
            self.assertFalse((output / 'common/kueue.json').exists())

    def test_toggling_kueue_removes_previous_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            common = root / 'dashboards/common'
            common.mkdir(parents=True)
            for name in ('base', 'kueue'):
                (common / (name + '.jsonnet')).write_text(json.dumps({'uid': name}))
            output = root / 'build'
            renderer.compile_dashboards(root, output, JSONNET, root, include_kueue=True)
            self.assertTrue((output / 'common/kueue.json').exists())
            renderer.compile_dashboards(root, output, JSONNET, root, include_kueue=False)
            self.assertFalse((output / 'common/kueue.json').exists())
            self.assertTrue((output / 'common/base.json').exists())

    def test_host_links_resolve_to_existing_dashboard_filters(self):
        build = PACKAGE / 'build'
        dashboard = json.loads((build / 'common/kueue.json').read_text())
        destinations = {}
        for source in (build / 'gpu').glob('*.json'):
            content = json.loads(source.read_text())
            destinations[content['uid']] = content
        for link in dashboard['links']:
            uid = urlparse(link['url']).path.split('/')[2]
            self.assertIn(uid, destinations)
            names = {v['name'] for v in destinations[uid]['templating']['list']}
            self.assertTrue({'hostname', 'instance_shape', 'oci_name'} <= names)
            self.assertIn('${hostname:queryparam}', link['url'])
            self.assertIn('from=${__from}&to=${__to}', link['url'])
        host = next(v for v in dashboard['templating']['list'] if v['name'] == 'hostname')
        self.assertTrue(host['multi'])
        self.assertFalse(host.get('allValue'))  # All must expand to actual hosts, not .*


if __name__ == '__main__':
    unittest.main()
