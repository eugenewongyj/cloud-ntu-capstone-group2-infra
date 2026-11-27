const ts = require('typescript');

module.exports = function (source) {
  const result = ts.transpileModule(source, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
      strict: true
    },
    reportDiagnostics: true
  });

  const errors = (result.diagnostics || [])
    .filter(d => d.category === ts.DiagnosticCategory.Error);

  if (errors.length) {
    throw new Error(
      ts.formatDiagnosticsWithColorAndContext(errors, {
        getCurrentDirectory: () => process.cwd(),
        getCanonicalFileName: f => f,
        getNewLine: () => '\n'
      })
    );
  }

  return result.outputText;
};
