import importlib.util
import unittest
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('catalog', root / 'scripts/update_sites.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    def test_normalizes_idn_wildcards_without_widening_subdomains(self):
        domains = catalog.parse_domains('*.BANK.RU\nlogin.other.ru\nбанк.рф\nbank.ru\n'.encode())
        self.assertEqual(domains, ['bank.ru', 'login.other.ru', 'xn--80ab2al.xn--p1ai'])

    def test_windows_1251_source(self):
        self.assertEqual(catalog.parse_domains('банк.рф\n'.encode('cp1251')), ['xn--80ab2al.xn--p1ai'])

    def test_rejects_public_suffixes_ips_urls_and_malformed_names(self):
        for value in ['ru', '*.ru', 'co.uk', 'github.io', '127.0.0.1', 'https://bank.ru', 'foo@bank.ru', 'a..ru', '-a.ru', 'a.ru/path', '<html>']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                catalog.parse_domains((value+'\n').encode())


if __name__ == '__main__':
    unittest.main()
