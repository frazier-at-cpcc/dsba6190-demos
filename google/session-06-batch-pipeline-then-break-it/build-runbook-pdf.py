#!/usr/bin/env python3
"""
Render the Session 6 RUNBOOK.md to a podium-readable PDF.

    python3 build-runbook-pdf.py

This is not a handout. It is read standing up, at arm's length, while running
commands. Body type is larger than the lab handouts, commands sit in boxes that
can be found without reading, and no step is allowed to split across a page.
"""

import re
import subprocess
from pathlib import Path

import markdown

HERE = Path(__file__).parent
BRAND = HERE.parent.parent.parent / "docs" / "syllabus" / "syllabus.css"


def brand_vars() -> str:
    css = BRAND.read_text()
    m = re.search(r":root\s*\{.*?\}", css, re.S)
    return m.group(0) if m else ""


CSS = """
@page {
  size: Letter;
  margin: 0.8in 0.7in 0.75in 0.7in;
  @top-left {
    width: 62%; content: "DSBA 6190  ·  SESSION 6  ·  LIVE DEMO RUNBOOK";
    font-family: var(--sans); font-size: 8pt; letter-spacing: .07em; color: var(--green);
    border-bottom: .9pt solid var(--gold); padding-bottom: 5pt; margin-bottom: 14pt; vertical-align: bottom;
  }
  @top-right {
    width: 38%; content: "1:30 to 2:30";
    font-family: var(--sans); font-size: 8pt; letter-spacing: .07em; color: var(--med);
    border-bottom: .9pt solid var(--gold); padding-bottom: 5pt; margin-bottom: 14pt;
    text-align: right; vertical-align: bottom;
  }
  @bottom-left {
    width: 70%; content: "A batch pipeline, then break it  ·  rehearsed 10 September 2026";
    font-family: var(--sans); font-size: 7.5pt; color: var(--med);
    border-top: .6pt solid var(--rule); padding-top: 5pt; margin-top: 10pt;
  }
  @bottom-right {
    width: 30%; content: counter(page) " of " counter(pages);
    font-family: var(--sans); font-size: 8.5pt; color: var(--med);
    border-top: .6pt solid var(--rule); padding-top: 5pt; margin-top: 10pt; text-align: right;
  }
}

body { font-family: var(--serif); font-size: 11.5pt; line-height: 1.44; color: var(--ore); margin: 0; }
p { margin: 0 0 .5em; }
strong { color: var(--ore); }

h1 { font-family: var(--sans); font-size: 21pt; color: var(--green); margin: 0 0 .15em;
     letter-spacing: -.01em; line-height: 1.1; }
h1 + p { font-size: 10.5pt; color: var(--med); margin-bottom: 1.1em; }

h2 { font-family: var(--sans); font-size: 13.5pt; color: var(--green); margin: 1.5em 0 .5em;
     padding-bottom: .22em; border-bottom: 1.4pt solid var(--gold); letter-spacing: .01em;
     break-after: avoid; }

/* A step is a unit. Never split one across a page. */
h3 { font-family: var(--sans); font-size: 12pt; color: var(--ore); margin: 1.15em 0 .4em;
     break-after: avoid; page-break-after: avoid; }
h3 .chip { font-size: 8.5pt; color: var(--green); background: var(--green-tint);
           border: .6pt solid var(--gold); border-radius: 2pt; padding: .8pt 4pt;
           margin-left: 6pt; letter-spacing: .04em; white-space: nowrap; }

pre { font-family: var(--mono); font-size: 11pt; line-height: 1.4;
      background: #FAF9F5; border: .8pt solid var(--rule); border-left: 3pt solid var(--green);
      padding: 7pt 9pt; margin: .5em 0 .6em; white-space: pre-wrap;
      break-inside: avoid; page-break-inside: avoid; }
code { font-family: var(--mono); font-size: .93em; background: var(--gold-tint); padding: .5pt 2.5pt; }
pre code { background: none; padding: 0; font-size: 1em; }

ul, ol { margin: 0 0 .6em; padding-left: 1.25em; }
li { margin-bottom: .22em; }

table { border-collapse: collapse; width: 100%; font-size: 10pt; margin: .5em 0 .9em;
        break-inside: avoid; page-break-inside: avoid; }
th { font-family: var(--sans); font-size: 8pt; letter-spacing: .06em; text-transform: uppercase;
     color: var(--med); text-align: left; background: var(--gold-tint);
     border-bottom: 1pt solid var(--gold); padding: 4pt 6pt; }
td { border-bottom: .5pt solid var(--rule); padding: 4pt 6pt; vertical-align: top; }

hr { border: 0; border-top: .8pt solid var(--rule); margin: 1.4em 0; }

blockquote { margin: 0 0 .7em; padding: 6pt 10pt; background: var(--green-tint);
             border-left: 3pt solid var(--green); }

del { color: var(--med); text-decoration-thickness: .6pt; }
del strong { color: var(--med); font-weight: 600; }

/* A paper checklist. The literal brackets are the boxes. */
li > del { display: inline; }

/* Warnings carry the session's own danger colour. */
.warn { background: #F8EDEC; border-left: 3pt solid var(--clay); padding: 7pt 10pt;
        margin: .6em 0 .8em; break-inside: avoid; }
.warn strong { color: var(--clay); }
"""


def build() -> Path:
    md = (HERE / "RUNBOOK.md").read_text()
    # The teardown checklist strikes out rows that do not apply rather than
    # deleting them, per DEMO-DEVELOPMENT-PLAN.md section 8. Python-Markdown has
    # no native ~~...~~, so it is converted before the document is rendered.
    md = re.sub(r"~~(.+?)~~", r"<del>\1</del>", md, flags=re.S)
    html_body = markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"])

    # Trailing "· slide N · M minutes" on a step heading becomes a chip.
    def chip(m):
        head = m.group(1)
        parts = [p.strip() for p in head.split("·")]
        if len(parts) >= 3 and "minute" in parts[-1]:
            label = " · ".join(parts[:-2])
            meta = " · ".join(parts[-2:])
            return f'<h3>{label}<span class="chip">{meta}</span></h3>'
        return m.group(0)

    html_body = re.sub(r"<h3>(.*?)</h3>", chip, html_body, flags=re.S)

    # Paragraphs that open with a bolded imperative are warnings.
    html_body = re.sub(
        r"<p>(<strong>(?:Do not|Never|Stop here|End here|Network contingency|The refusal|If the room)[^<]*</strong>.*?)</p>",
        r'<div class="warn"><p>\1</p></div>', html_body, flags=re.S)

    html = ("<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>"
            "<title>Session 6 live demo runbook</title>"
            f"<style>{brand_vars()}{CSS}</style></head><body>{html_body}</body></html>")

    tmp = HERE / ".runbook.html"
    tmp.write_text(html)
    pdf = HERE / "Session-06-Live-Demo-Runbook.pdf"
    r = subprocess.run(["weasyprint", str(tmp), str(pdf)], capture_output=True, text=True, cwd=HERE)
    tmp.unlink(missing_ok=True)
    if r.returncode != 0:
        raise SystemExit(f"weasyprint failed: {r.stderr[:400]}")
    return pdf


if __name__ == "__main__":
    p = build()
    print(f"  {p.name}  ({p.stat().st_size // 1024} KB)")
