import unittest

import sandbox


class PersistentReplTests(unittest.TestCase):
    def setUp(self):
        sandbox._REPL_SESSIONS.clear()

    def tearDown(self):
        sandbox._REPL_SESSIONS.clear()

    def test_variables_persist_within_one_session(self):
        first = sandbox.run_repl("total = 40\nprint(total + 2)", "/tmp", "chat_one")
        second = sandbox.run_repl("total += 1\nprint(total)", "/tmp", "chat_one")

        self.assertEqual(first["status"], "success")
        self.assertEqual(first["output"].strip(), "42")
        self.assertEqual(second["status"], "success")
        self.assertEqual(second["output"].strip(), "41")

    def test_sessions_are_isolated(self):
        sandbox.run_repl("secret_value = 77", "/tmp", "chat_one")
        other = sandbox.run_repl("print(secret_value)", "/tmp", "chat_two")

        self.assertEqual(other["status"], "error")
        self.assertIn("NameError", other["error"])

    def test_reset_clears_only_the_selected_session(self):
        sandbox.run_repl("value = 9", "/tmp", "chat_one")
        sandbox.run_repl("value = 3", "/tmp", "chat_two")

        reset = sandbox.reset_repl("chat_one")
        first = sandbox.run_repl("print(value)", "/tmp", "chat_one")
        second = sandbox.run_repl("print(value)", "/tmp", "chat_two")

        self.assertTrue(reset["ok"])
        self.assertTrue(reset["reset"])
        self.assertEqual(first["status"], "error")
        self.assertEqual(second["output"].strip(), "3")

    def test_repl_keeps_the_existing_ast_security_boundary(self):
        result = sandbox.run_repl("import os", "/tmp", "chat_security")
        self.assertEqual(result["status"], "error")
        self.assertIn("PermissionError", result["error"])

    def test_session_identifier_is_validated(self):
        result = sandbox.run_repl("print(1)", "/tmp", "../escape")
        self.assertEqual(result["status"], "error")
        self.assertIn("Invalid REPL session id", result["error"])


if __name__ == "__main__":
    unittest.main()
