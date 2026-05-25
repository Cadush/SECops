#!/bin/bash
# SECops - Gerador de Relatório HTML
# Uso: bash scripts/report-html.sh reports/<timestamp>

set -e

REPORT_DIR="${1:?Uso: $0 <diretório_de_reports>}"
OUTPUT="$REPORT_DIR/report.html"

if [ ! -d "$REPORT_DIR" ]; then
    echo "Erro: diretório '$REPORT_DIR' não encontrado"
    exit 1
fi

SCAN_DATE=$(basename "$REPORT_DIR" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
SCAN_USER=$(whoami)
SCAN_HOST=$(hostname)

# Contadores
CRITICAL=0; HIGH=0; MEDIUM=0; LOW=0; INFO=0

count_audit() {
    local file="$REPORT_DIR/audit-config.json"
    [ -f "$file" ] || return
    CRITICAL=$((CRITICAL + $(jq '[.findings[] | select(.severity == "CRITICAL")] | length' "$file" 2>/dev/null || echo 0)))
    HIGH=$((HIGH + $(jq '[.findings[] | select(.severity == "HIGH")] | length' "$file" 2>/dev/null || echo 0)))
    MEDIUM=$((MEDIUM + $(jq '[.findings[] | select(.severity == "MEDIUM")] | length' "$file" 2>/dev/null || echo 0)))
    LOW=$((LOW + $(jq '[.findings[] | select(.severity == "LOW")] | length' "$file" 2>/dev/null || echo 0)))
}

count_bandit() {
    local file="$REPORT_DIR/bandit.json"
    [ -f "$file" ] || return
    CRITICAL=$((CRITICAL + $(jq '[.results[] | select(.issue_severity == "CRITICAL")] | length' "$file" 2>/dev/null || echo 0)))
    HIGH=$((HIGH + $(jq '[.results[] | select(.issue_severity == "HIGH")] | length' "$file" 2>/dev/null || echo 0)))
    MEDIUM=$((MEDIUM + $(jq '[.results[] | select(.issue_severity == "MEDIUM")] | length' "$file" 2>/dev/null || echo 0)))
    LOW=$((LOW + $(jq '[.results[] | select(.issue_severity == "LOW")] | length' "$file" 2>/dev/null || echo 0)))
}

count_trivy() {
    local file="$REPORT_DIR/trivy-fs.json"
    [ -f "$file" ] || return
    CRITICAL=$((CRITICAL + $(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$file" 2>/dev/null || echo 0)))
    HIGH=$((HIGH + $(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$file" 2>/dev/null || echo 0)))
    MEDIUM=$((MEDIUM + $(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "$file" 2>/dev/null || echo 0)))
    LOW=$((LOW + $(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "LOW")] | length' "$file" 2>/dev/null || echo 0)))
}

count_gitleaks() {
    local file="$REPORT_DIR/gitleaks.json"
    [ -f "$file" ] || return
    local c=$(jq 'length' "$file" 2>/dev/null || echo 0)
    HIGH=$((HIGH + c))
}

count_checkov() {
    local file="$REPORT_DIR/checkov.json"
    [ -f "$file" ] || return
    local c=$(jq '[.results?.failed_checks[]?] | length' "$file" 2>/dev/null || echo 0)
    MEDIUM=$((MEDIUM + c))
}

count_audit
count_bandit
count_trivy
count_gitleaks
count_checkov

TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW + INFO))

cat > "$OUTPUT" << HEADER
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Relatorio de Seguranca da Informacao</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0d1117; color: #c9d1d9; line-height: 1.6; }
.container { max-width: 1200px; margin: 0 auto; padding: 20px; }
h1 { color: #58a6ff; margin-bottom: 5px; font-size: 1.6em; }
.meta { color: #8b949e; margin-bottom: 25px; font-size: 0.9em; }
.meta span { margin-right: 20px; }
.chart-section { display: flex; align-items: center; gap: 40px; margin-bottom: 30px; padding: 25px; background: #161b22; border: 1px solid #30363d; border-radius: 8px; }
.pie-container { position: relative; width: 200px; height: 200px; }
.pie-container canvas { width: 200px; height: 200px; }
.pie-total { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); text-align: center; }
.pie-total .number { font-size: 2.2em; font-weight: bold; color: #e6edf3; }
.pie-total .label { font-size: 0.8em; color: #8b949e; }
.legend { display: flex; flex-direction: column; gap: 10px; }
.legend-item { display: flex; align-items: center; gap: 10px; font-size: 0.95em; }
.legend-color { width: 14px; height: 14px; border-radius: 3px; }
.legend-count { font-weight: bold; min-width: 30px; }
.btn-pdf { display: inline-block; margin-bottom: 25px; padding: 10px 20px; background: #238636; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-size: 0.9em; text-decoration: none; }
.btn-pdf:hover { background: #2ea043; }
.section { background: #161b22; border: 1px solid #30363d; border-radius: 8px; margin-bottom: 20px; overflow: hidden; }
.section-header { padding: 15px 20px; background: #1c2128; border-bottom: 1px solid #30363d; display: flex; justify-content: space-between; align-items: center; }
.section-header h2 { font-size: 1.1em; color: #e6edf3; }
.badge { padding: 3px 10px; border-radius: 12px; font-size: 0.8em; font-weight: bold; }
.badge-critical { background: #f8514922; color: #f85149; }
.badge-high { background: #f0883e22; color: #f0883e; }
.badge-medium { background: #d2992222; color: #d29922; }
.badge-low { background: #3fb95022; color: #3fb950; }
.section-body { padding: 0; max-height: 600px; overflow-y: auto; }
table { width: 100%; border-collapse: collapse; }
th { background: #1c2128; padding: 10px 15px; text-align: left; font-size: 0.85em; color: #8b949e; position: sticky; top: 0; }
td { padding: 10px 15px; border-top: 1px solid #21262d; font-size: 0.9em; vertical-align: top; }
tr:hover { background: #1c2128; }
.sev { padding: 2px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; white-space: nowrap; }
.sev-CRITICAL { background: #f8514933; color: #f85149; }
.sev-HIGH { background: #f0883e33; color: #f0883e; }
.sev-MEDIUM { background: #d2992233; color: #d29922; }
.sev-LOW { background: #3fb95033; color: #3fb950; }
.empty { padding: 30px; text-align: center; color: #3fb950; }
.footer { text-align: center; color: #8b949e; margin-top: 30px; padding-top: 20px; border-top: 1px solid #30363d; font-size: 0.85em; }
code { background: #1c2128; padding: 2px 6px; border-radius: 4px; font-size: 0.85em; }
@media print { .btn-pdf { display: none; } body { background: #fff; color: #000; } .container { max-width: 100%; } .section, .chart-section { border-color: #ccc; background: #fff; } .section-header { background: #f5f5f5; } th { background: #f5f5f5; } h1 { color: #0366d6; } .footer { color: #666; } }
</style>
</head>
<body>
<div class="container">
<h1>Relatorio de Seguranca da Informacao</h1>
HEADER

cat >> "$OUTPUT" << EOF
<div class="meta">
<span><strong>Data do scan:</strong> $SCAN_DATE</span>
<span><strong>Executado por:</strong> $SCAN_USER@$SCAN_HOST</span>
</div>

<button class="btn-pdf" onclick="window.print()">Exportar PDF</button>

<div class="chart-section">
<div class="pie-container">
<canvas id="pieChart" width="200" height="200"></canvas>
<div class="pie-total"><div class="number">$TOTAL</div><div class="label">Total</div></div>
</div>
<div class="legend">
<div class="legend-item"><div class="legend-color" style="background:#f85149;"></div><span class="legend-count">$CRITICAL</span> Critical</div>
<div class="legend-item"><div class="legend-color" style="background:#f0883e;"></div><span class="legend-count">$HIGH</span> High</div>
<div class="legend-item"><div class="legend-color" style="background:#d29922;"></div><span class="legend-count">$MEDIUM</span> Medium</div>
<div class="legend-item"><div class="legend-color" style="background:#3fb950;"></div><span class="legend-count">$LOW</span> Low</div>
</div>
</div>
EOF

# ===== AUDIT CONFIG =====
AUDIT_FILE="$REPORT_DIR/audit-config.json"
if [ -f "$AUDIT_FILE" ] && [ "$(jq '.findings | length' "$AUDIT_FILE" 2>/dev/null)" -gt 0 ]; then
    AUDIT_COUNT=$(jq '.findings | length' "$AUDIT_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>Configuracao e Secrets Expostos</h2><span class="badge badge-critical">$AUDIT_COUNT findings</span></div>
<div class="section-body"><table>
<tr><th>Severidade</th><th>Categoria</th><th>Arquivo:Linha</th><th>Detalhe</th></tr>
EOF
    jq -r '.findings[] | "<tr><td><span class=\"sev sev-\(.severity)\">\(.severity)</span></td><td>\(.category)</td><td><code>\(.file)</code></td><td>\(.detail)</td></tr>"' "$AUDIT_FILE" >> "$OUTPUT"
    echo "</table></div></div>" >> "$OUTPUT"
fi

# ===== SAST (Bandit) =====
BANDIT_FILE="$REPORT_DIR/bandit.json"
if [ -f "$BANDIT_FILE" ] && [ "$(jq '.results | length' "$BANDIT_FILE" 2>/dev/null)" -gt 0 ]; then
    BANDIT_COUNT=$(jq '.results | length' "$BANDIT_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>SAST - Bandit (Python)</h2><span class="badge badge-high">$BANDIT_COUNT findings</span></div>
<div class="section-body"><table>
<tr><th>Severidade</th><th>Arquivo</th><th>Linha</th><th>Vulnerabilidade</th><th>CWE</th></tr>
EOF
    jq -r '.results[] | "<tr><td><span class=\"sev sev-\(.issue_severity)\">\(.issue_severity)</span></td><td><code>\(.filename)</code></td><td>\(.line_number)</td><td>\(.issue_text)</td><td>CWE-\(.issue_cwe.id)</td></tr>"' "$BANDIT_FILE" >> "$OUTPUT"
    echo "</table></div></div>" >> "$OUTPUT"
fi

# ===== SCA (Trivy) =====
TRIVY_FILE="$REPORT_DIR/trivy-fs.json"
if [ -f "$TRIVY_FILE" ] && [ "$(jq '[.Results[]?.Vulnerabilities[]?] | length' "$TRIVY_FILE" 2>/dev/null)" -gt 0 ]; then
    TRIVY_COUNT=$(jq '[.Results[]?.Vulnerabilities[]?] | length' "$TRIVY_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>SCA - Dependencias Vulneraveis (Trivy)</h2><span class="badge badge-critical">$TRIVY_COUNT CVEs</span></div>
<div class="section-body"><table>
<tr><th>Severidade</th><th>Pacote</th><th>Versao</th><th>Fix</th><th>CVE</th><th>Descricao</th></tr>
EOF
    jq -r '.Results[]?.Vulnerabilities[]? | "<tr><td><span class=\"sev sev-\(.Severity)\">\(.Severity)</span></td><td><code>\(.PkgName)</code></td><td>\(.InstalledVersion)</td><td>\(.FixedVersion // "—")</td><td>\(.VulnerabilityID)</td><td>\(.Title // .Description | .[0:80])...</td></tr>"' "$TRIVY_FILE" >> "$OUTPUT"
    echo "</table></div></div>" >> "$OUTPUT"
fi

# ===== Secrets (Gitleaks) =====
GITLEAKS_FILE="$REPORT_DIR/gitleaks.json"
if [ -f "$GITLEAKS_FILE" ] && [ "$(jq 'length' "$GITLEAKS_FILE" 2>/dev/null)" -gt 0 ]; then
    GL_COUNT=$(jq 'length' "$GITLEAKS_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>Secrets - Gitleaks</h2><span class="badge badge-high">$GL_COUNT secrets</span></div>
<div class="section-body"><table>
<tr><th>Tipo</th><th>Arquivo</th><th>Linha</th><th>Match</th></tr>
EOF
    jq -r '.[] | "<tr><td>\(.RuleID)</td><td><code>\(.File)</code></td><td>\(.StartLine)</td><td><code>\(.Match[0:50])...</code></td></tr>"' "$GITLEAKS_FILE" >> "$OUTPUT"
    echo "</table></div></div>" >> "$OUTPUT"
else
    cat >> "$OUTPUT" << 'EOF'
<div class="section">
<div class="section-header"><h2>Secrets - Gitleaks</h2><span class="badge badge-low">0 secrets</span></div>
<div class="section-body"><div class="empty">Nenhum secret detectado no historico git</div></div></div>
EOF
fi

# ===== Secrets (TruffleHog) =====
TRUFFLE_FILE="$REPORT_DIR/trufflehog.json"
if [ -f "$TRUFFLE_FILE" ] && [ -s "$TRUFFLE_FILE" ] && [ "$(wc -l < "$TRUFFLE_FILE")" -gt 0 ]; then
    TH_COUNT=$(wc -l < "$TRUFFLE_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>Secrets - TruffleHog</h2><span class="badge badge-high">$TH_COUNT findings</span></div>
<div class="section-body"><table>
<tr><th>Detector</th><th>Arquivo</th><th>Linha</th><th>Secret (redacted)</th><th>Verificado</th></tr>
EOF
    while IFS= read -r line; do
        detector=$(echo "$line" | jq -r '.DetectorName // "unknown"' 2>/dev/null)
        file=$(echo "$line" | jq -r '.SourceMetadata.Data.Filesystem.file // "—"' 2>/dev/null)
        lineno=$(echo "$line" | jq -r '.SourceMetadata.Data.Filesystem.line // "—"' 2>/dev/null)
        raw=$(echo "$line" | jq -r '.Raw // ""' 2>/dev/null | cut -c1-20)
        verified=$(echo "$line" | jq -r 'if .Verified then "Sim" else "Nao" end' 2>/dev/null)
        echo "<tr><td><strong>$detector</strong></td><td><code>$file</code></td><td>$lineno</td><td><code>${raw}...</code></td><td>$verified</td></tr>" >> "$OUTPUT"
    done < "$TRUFFLE_FILE"
    echo "</table></div></div>" >> "$OUTPUT"
fi

# ===== IaC (Checkov) =====
CHECKOV_FILE="$REPORT_DIR/checkov.json"
if [ -f "$CHECKOV_FILE" ] && [ "$(jq '.results?.failed_checks // [] | length' "$CHECKOV_FILE" 2>/dev/null)" -gt 0 ]; then
    CK_COUNT=$(jq '.results.failed_checks | length' "$CHECKOV_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>IaC - Checkov</h2><span class="badge badge-medium">$CK_COUNT findings</span></div>
<div class="section-body"><table>
<tr><th>Check</th><th>Recurso</th><th>Arquivo</th><th>Guideline</th></tr>
EOF
    jq -r '.results.failed_checks[]? | "<tr><td>\(.check_id)</td><td><code>\(.resource)</code></td><td>\(.file_path):\(.file_line_range[0])</td><td>\(.guideline // "—")</td></tr>"' "$CHECKOV_FILE" >> "$OUTPUT"
    echo "</table></div></div>" >> "$OUTPUT"
fi

# ===== Container (Hadolint) =====
HADOLINT_FILE="$REPORT_DIR/hadolint-Dockerfile.txt"
if [ -f "$HADOLINT_FILE" ] && [ -s "$HADOLINT_FILE" ]; then
    HL_COUNT=$(wc -l < "$HADOLINT_FILE")
    cat >> "$OUTPUT" << EOF
<div class="section">
<div class="section-header"><h2>Container - Hadolint</h2><span class="badge badge-medium">$HL_COUNT findings</span></div>
<div class="section-body"><table>
<tr><th>Linha</th><th>Regra</th><th>Mensagem</th></tr>
EOF
    while IFS= read -r line; do
        echo "<tr><td colspan=\"3\"><code>$line</code></td></tr>" >> "$OUTPUT"
    done < "$HADOLINT_FILE"
    echo "</table></div></div>" >> "$OUTPUT"
fi

# Footer + Pie Chart JS
cat >> "$OUTPUT" << EOF
<div class="footer">
<p>Todos os direitos reservados a Carlos Eduardo</p>
</div>
</div>
<script>
(function() {
    var canvas = document.getElementById('pieChart');
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    var data = [{v:$CRITICAL,c:'#f85149'},{v:$HIGH,c:'#f0883e'},{v:$MEDIUM,c:'#d29922'},{v:$LOW,c:'#3fb950'}];
    var total = data.reduce(function(s,d){return s+d.v;},0);
    if (total === 0) return;
    var start = -Math.PI/2;
    var cx = 100, cy = 100, r = 85;
    data.forEach(function(d) {
        if (d.v === 0) return;
        var slice = (d.v/total) * 2 * Math.PI;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.arc(cx, cy, r, start, start + slice);
        ctx.closePath();
        ctx.fillStyle = d.c;
        ctx.fill();
        start += slice;
    });
    ctx.beginPath();
    ctx.arc(cx, cy, 55, 0, 2*Math.PI);
    ctx.fillStyle = '#161b22';
    ctx.fill();
})();
</script>
</body>
</html>
EOF

echo "Relatorio gerado: $OUTPUT"
echo "  Abra com: xdg-open $OUTPUT"
echo "  Para PDF: abra no navegador e clique em 'Exportar PDF'"
