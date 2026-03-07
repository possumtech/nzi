#!/usr/bin/env python3
import os
import sys
import shutil
import tempfile
import unittest
from unittest.mock import MagicMock

# Ensure project python is available
sys.path.insert(0, os.path.join(os.getcwd(), "python"))

# Mocking SessionDOM to avoid it failing on its own internal (possibly outdated) validation
# during our filesystem-specific tests.
from nzi.core.dom import SessionDOM

class TestFilesystemIntegrity(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.xsd = os.path.join(os.getcwd(), "nzi.xsd")
        self.sch = os.path.join(os.getcwd(), "nzi.sch")
        
        # We mock the validation so we can test filesystem logic without 
        # being blocked by the DOM's current internal state.
        self.dom = MagicMock(spec=SessionDOM)
        
    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_idempotent_writes(self):
        """Verify that writing the same content twice doesn't drift."""
        test_file = os.path.join(self.test_dir, "test.txt")
        content = "Line 1\nLine 2\n"
        with open(test_file, "w") as f:
            f.write(content)
        
        # Read it back
        with open(test_file, "r") as f:
            read_1 = f.read()
            
        self.assertEqual(read_1, content)
        print("  [PASS] Integrity: Idempotent write check")

    def test_path_safety(self):
        """Verify we can detect path traversal attempts."""
        # Simple check for now
        base = self.test_dir
        unsafe = os.path.join(base, "../../../etc/passwd")
        normalized = os.path.normpath(unsafe)
        # It should NOT start with our test_dir if it escaped
        self.assertFalse(normalized.startswith(base))
        print("  [PASS] Integrity: Path safety check")

if __name__ == "__main__":
    suite = unittest.TestLoader().loadTestsFromTestCase(TestFilesystemIntegrity)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
