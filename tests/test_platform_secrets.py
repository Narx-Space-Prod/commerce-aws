import base64
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parents[1] / 'scripts/secrets.py'


class PlatformSecrets(unittest.TestCase):
    def execute(self, existing, environment=None, context='commerce-aws'):
        output = io.StringIO()
        with patch('sys.argv', ['secrets.py', 'slack']), \
             patch.dict(os.environ, environment or {}, clear=False), \
             patch('subprocess.check_output', return_value=context), \
             patch('subprocess.run', side_effect=[existing, subprocess.CompletedProcess([], 0)]) as command, \
             patch('getpass.getpass', side_effect=AssertionError('Unexpected interactive prompt')), \
             contextlib.redirect_stdout(output):
            try:
                runpy.run_path(str(SCRIPT), run_name='__main__')
            except SystemExit as error:
                return command.call_args_list, output.getvalue(), str(error)
        return command.call_args_list, output.getvalue(), None

    def test_access_error_does_not_create_or_prompt(self):
        calls, _, error = self.execute(subprocess.CompletedProcess([], 1, stdout=b''))
        self.assertIn('Cannot check existing secret', error)
        self.assertEqual(len(calls), 1)

    def test_existing_secret_is_preserved(self):
        calls, _, _ = self.execute(subprocess.CompletedProcess([], 0, stdout=b'secret/slack-notifications'))
        self.assertEqual(len(calls), 1)

    def test_wrong_context_stops_before_mutation(self):
        calls, _, error = self.execute(subprocess.CompletedProcess([], 0, stdout=b''), context='other-cluster')
        self.assertIn('dedicated commerce-aws', error)
        self.assertEqual(len(calls), 0)

    def test_injected_secret_uses_stdin_without_logging(self):
        value = 'https://hooks.slack.com/services/test'
        calls, output, error = self.execute(subprocess.CompletedProcess([], 0, stdout=b''), {'SLACK_WEBHOOK': value})
        self.assertIsNone(error)
        creation = calls[1]
        self.assertEqual(creation.args[0][-3:], ['create', '-f', '-'])
        manifest = json.loads(creation.kwargs['input'])
        self.assertEqual(base64.b64decode(manifest['data']['webhook']).decode(), value)
        self.assertNotIn(value, output)
        self.assertNotIn(value, ' '.join(creation.args[0]))


if __name__ == '__main__':
    unittest.main()
