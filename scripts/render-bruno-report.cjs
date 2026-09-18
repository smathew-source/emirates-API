const fs = require("fs");
const path = require("path");

const inputPath = process.argv[2] || "reports/github-actions.json";
const outputPath = process.argv[3] || "reports/github-actions.html";

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function readReport() {
  if (!fs.existsSync(inputPath)) {
    return { missing: true, iterations: [] };
  }
  return { missing: false, iterations: JSON.parse(fs.readFileSync(inputPath, "utf8")) };
}

const report = readReport();
const results = report.iterations.flatMap(iteration => iteration.results || []);
const tests = results.flatMap(result => (result.testResults || []).map(test => ({
  request: result.name || result.test?.filename || result.path,
  status: test.status,
  description: test.description,
  error: test.error || ""
})));
const passedRequests = results.filter(result => result.status === "pass").length;
const failedRequests = results.length - passedRequests;
const passedTests = tests.filter(test => test.status === "pass").length;
const failedTests = tests.length - passedTests;
const overallPass = !report.missing && failedRequests === 0 && failedTests === 0;

const requestRows = results.map(result => `
  <tr>
    <td>${escapeHtml(result.name || result.test?.filename || result.path)}</td>
    <td>${escapeHtml(result.response?.status || "-")}</td>
    <td>${escapeHtml(result.response?.duration ?? "-")} ms</td>
    <td><span class="badge ${result.status === "pass" ? "pass" : "fail"}">${escapeHtml(result.status || "unknown")}</span></td>
  </tr>`).join("");

const testRows = tests.map(test => `
  <tr>
    <td>${escapeHtml(test.request)}</td>
    <td>${escapeHtml(test.description)}</td>
    <td><span class="badge ${test.status === "pass" ? "pass" : "fail"}">${escapeHtml(test.status)}</span></td>
    <td>${escapeHtml(test.error)}</td>
  </tr>`).join("");

const missingMessage = report.missing
  ? `<div class="notice">The JSON report was not created. Check the Bruno step log.</div>`
  : "";

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Emirates API CI Report</title>
  <style>
    :root { color-scheme: light; font-family: ui-sans-serif, system-ui, sans-serif; background: #f4f7f9; color: #17212b; }
    body { margin: 0; padding: 32px; }
    main { max-width: 1100px; margin: auto; }
    h1 { margin: 0 0 8px; font-size: 30px; }
    .subtitle { color: #5b6873; margin-bottom: 24px; }
    .banner { padding: 16px 20px; border-radius: 10px; color: white; font-weight: 700; margin-bottom: 20px; background: ${overallPass ? "#16794c" : "#b42318"}; }
    .cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
    .card { background: white; border: 1px solid #d9e0e5; border-radius: 10px; padding: 16px; }
    .label { color: #5b6873; font-size: 13px; }
    .value { display: block; font-size: 25px; font-weight: 700; margin-top: 5px; }
    section { background: white; border: 1px solid #d9e0e5; border-radius: 10px; padding: 18px; margin-top: 16px; overflow-x: auto; }
    h2 { margin: 0 0 12px; font-size: 19px; }
    table { border-collapse: collapse; width: 100%; min-width: 650px; }
    th, td { text-align: left; padding: 10px; border-top: 1px solid #e7ecef; vertical-align: top; }
    th { color: #5b6873; font-size: 13px; }
    .badge { display: inline-block; border-radius: 999px; padding: 3px 9px; font-size: 12px; font-weight: 700; text-transform: uppercase; }
    .pass { color: #075e3d; background: #d9f5e8; }
    .fail { color: #8f1d14; background: #fde3e1; }
    .notice { background: #fff3cd; border: 1px solid #f1d98b; padding: 14px; border-radius: 8px; }
    @media (max-width: 700px) { body { padding: 16px; } .cards { grid-template-columns: repeat(2, 1fr); } }
  </style>
</head>
<body>
  <main>
    <h1>Emirates API CI Report</h1>
    <div class="subtitle">Generated from Bruno collection results</div>
    <div class="banner">${overallPass ? "PASS - all requests and tests passed" : "FAIL - review the failed request or test"}</div>
    ${missingMessage}
    <div class="cards">
      <div class="card"><span class="label">Requests passed</span><span class="value">${passedRequests}/${results.length}</span></div>
      <div class="card"><span class="label">Requests failed</span><span class="value">${failedRequests}</span></div>
      <div class="card"><span class="label">Tests passed</span><span class="value">${passedTests}/${tests.length}</span></div>
      <div class="card"><span class="label">Tests failed</span><span class="value">${failedTests}</span></div>
    </div>
    <section><h2>Requests</h2><table><thead><tr><th>Request</th><th>HTTP</th><th>Duration</th><th>Status</th></tr></thead><tbody>${requestRows || "<tr><td colspan=\"4\">No request results</td></tr>"}</tbody></table></section>
    <section><h2>Tests</h2><table><thead><tr><th>Request</th><th>Test</th><th>Status</th><th>Error</th></tr></thead><tbody>${testRows || "<tr><td colspan=\"4\">No test results</td></tr>"}</tbody></table></section>
  </main>
</body>
</html>`;

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, html);
console.log(`Wrote ${outputPath}`);
