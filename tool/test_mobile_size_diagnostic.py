"""Check that model size rejection reports only configurations actually tried."""

import ast
import unittest
from pathlib import Path


class MobileSizeDiagnosticTest(unittest.TestCase):
    def test_size_failure_does_not_claim_untried_depth(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / "tool/train_max_aura_brain.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        function = next(node for node in tree.body
                        if isinstance(node, ast.FunctionDef) and node.name == "train_mobile_preset")
        rejection = next(node for node in function.body
                         if isinstance(node, ast.If)
                         and isinstance(node.test, ast.Compare)
                         and isinstance(node.test.left, ast.Name)
                         and node.test.left.id == "selected"
                         and isinstance(node.test.ops[0], ast.Is))
        code = compile(ast.fix_missing_locations(ast.Module(body=[rejection], type_ignores=[])),
                       "train_max_aura_brain.py", "exec")
        with self.assertRaises(SystemExit) as error:
            exec(code, {"selected": None, "MAX_MOBILE_MODEL_BYTES": 4194304,
                        "MOBILE_SIZE_TRIALS": root / "tool/reports/mobile_size_trials.json",
                        "ROOT": root})
        message = str(error.exception)
        self.assertIn("4194304 bytes", message)
        self.assertIn("all tested configurations", message)
        self.assertIn("tool/reports/mobile_size_trials.json", message)
        self.assertNotIn("max_depth=8", message)


if __name__ == "__main__":
    unittest.main()
