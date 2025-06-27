#!/bin/bash

forge coverage --ir-minimum --report lcov && genhtml lcov.info --output-directory coverage-report

set -e

# Paths
REPORT_DIR="coverage-report"
OUT_MAIN="$REPORT_DIR/coverage-main.pdf"
OUT_SRC="$REPORT_DIR/coverage-src.pdf"
OUT_TEST="$REPORT_DIR/coverage-test.pdf"
OUT_SCRIPT="$REPORT_DIR/coverage-script.pdf"
OUT_FULL="$REPORT_DIR/coverage-full.pdf"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Function to convert HTML to PDF if the HTML exists
convert_html_to_pdf() {
  local html_path="$1"
  local pdf_path="$2"
  if [ -f "$html_path" ]; then
    echo "Converting $html_path to $pdf_path"
    "$CHROME" --headless --disable-gpu --print-to-pdf="$pdf_path" "$html_path"
  else
    echo "Skipping $html_path (not found)"
  fi
}

# Convert each section
convert_html_to_pdf "$REPORT_DIR/index.html" "$OUT_MAIN"
convert_html_to_pdf "$REPORT_DIR/src/index.html" "$OUT_SRC"
convert_html_to_pdf "$REPORT_DIR/test/index.html" "$OUT_TEST"
convert_html_to_pdf "$REPORT_DIR/script/index.html" "$OUT_SCRIPT"

# Merge PDFs (only those that exist)
PDFS=()
for pdf in "$OUT_MAIN" "$OUT_SRC" "$OUT_TEST" "$OUT_SCRIPT"; do
  [ -f "$pdf" ] && PDFS+=("$pdf")
done

if [ ${#PDFS[@]} -gt 0 ]; then
  echo "Merging PDFs into $OUT_FULL"
  pdfunite "${PDFS[@]}" "$OUT_FULL"
  echo "Combined PDF report generated at $OUT_FULL"
else
  echo "No PDFs found to merge."
fi