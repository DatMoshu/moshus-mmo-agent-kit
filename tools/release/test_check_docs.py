import importlib.util
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('check_docs',Path(__file__).with_name('check_docs.py'))
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

class LinkCheckTests(unittest.TestCase):
    def test_missing_files_and_anchors_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); f=root/'README.md'
            f.write_text('# Home\n[bad](missing.md)\n[bad](#unknown)\n',encoding='utf-8')
            count,errors=mod.check(root,[f])
            self.assertEqual(count,2); self.assertEqual(len(errors),2)

    def test_local_links_encoded_names_duplicates_and_fences(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); f=root/'README.md'; target=root/'other page.md'
            target.write_text('# A heading\n# A heading\n',encoding='utf-8')
            f.write_text('# Home\n[ok](other%20page.md#a-heading-1)\n[ok](#home)\n[remote](https://example.com/404)\n```md\n[example](missing.md)\n```\n`[literal](missing.md)`\n',encoding='utf-8')
            count,errors=mod.check(root,[f,target])
            self.assertEqual(count,2); self.assertEqual(errors,[])

if __name__=='__main__': unittest.main()
