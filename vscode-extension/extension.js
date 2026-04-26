// track4blog VS Code extension.
//
// One command: track4blog.toggle. Bound to the Explorer right-click menu,
// the editor-tab right-click menu, and the in-editor right-click menu.
// Calls scripts/track4blog.sh inside the blogTrack repo, which flips
// the file's presence in scripts/devlog-config.json. The cron reads
// that config on its next run.

const path = require('path');
const { exec } = require('child_process');
const vscode = require('vscode');

function defaultScriptPath() {
  const home = process.env.HOME || process.env.USERPROFILE || '';
  return path.join(home, 'blogTrack', 'scripts', 'track4blog.sh');
}

function quoted(s) {
  return `"${s.replace(/"/g, '\\"')}"`;
}

function resolveScriptPath() {
  const cfg = vscode.workspace.getConfiguration('track4blog');
  const configured = (cfg.get('scriptPath') || '').trim();
  return configured || defaultScriptPath();
}

function activate(context) {
  // --- toggle a source on/off in the watches list -------------------
  const toggleCmd = vscode.commands.registerCommand('track4blog.toggle', async (uri) => {
    const scriptPath = resolveScriptPath();

    // Resolve target file: prefer the explorer right-click URI, then the
    // active editor's document URI. Multi-select in the explorer passes
    // each URI individually as separate command invocations.
    let filePath;
    if (uri && uri.fsPath) {
      filePath = uri.fsPath;
    } else if (vscode.window.activeTextEditor) {
      filePath = vscode.window.activeTextEditor.document.uri.fsPath;
    } else {
      vscode.window.showErrorMessage('track4blog: no file selected');
      return;
    }

    exec(`${quoted(scriptPath)} ${quoted(filePath)}`, (err, _stdout, stderr) => {
      if (err) {
        const detail = (stderr || err.message || '').trim();
        vscode.window.showErrorMessage(`track4blog: ${detail || 'script failed'}`);
        return;
      }
      vscode.window.setStatusBarMessage(
        `track4blog: toggled ${path.basename(filePath)}`,
        4000
      );
    });
  });

  // --- set the destination blog repo (one per install) --------------
  const setDestCmd = vscode.commands.registerCommand('track4blog.setDestination', async () => {
    const scriptPath = resolveScriptPath();

    const destPath = await vscode.window.showInputBox({
      prompt: 'Absolute path of the destination blog repo (every tracked source publishes into this site)',
      placeHolder: '/Users/you/path/to/blog-repo',
      ignoreFocusOut: true,
      validateInput: (v) => {
        if (!v) return 'path required';
        if (!path.isAbsolute(v)) return 'must be an absolute path';
        return null;
      }
    });
    if (!destPath) return; // user cancelled

    exec(`${quoted(scriptPath)} --set-destination ${quoted(destPath)}`, (err, _stdout, stderr) => {
      if (err) {
        const detail = (stderr || err.message || '').trim();
        vscode.window.showErrorMessage(`track4blog: ${detail || 'set-destination failed'}`);
        return;
      }
      vscode.window.setStatusBarMessage(
        `track4blog: destination set to ${destPath}`,
        4000
      );
    });
  });

  context.subscriptions.push(toggleCmd, setDestCmd);
}

function deactivate() {}

module.exports = { activate, deactivate };
