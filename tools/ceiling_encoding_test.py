import unittest

from tools.baker import gen_nav


class CeilingEncodingTest(unittest.TestCase):
    def test_absolute_heights_and_source_kinds(self):
        surfaces = {
            (0, 0): ((139.1, "terrain"),),
            (1, 0): ((126.0, "terrain"),),
            (3, 0): ((8.0, "structure"),),
            (3, 1): ((10.0, "structure"),),
            (3, 2): ((-1.0, "structure"),),
        }
        self.assertEqual(gen_nav.encode_ceilings(surfaces), "BkrEgCg+DgEhIBhKBf")
        self.assertEqual(gen_nav.encode_ceilings({}), "")
