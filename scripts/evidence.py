"""Shared math_evidence formatting for the job summary and the PR comment.

Both run.sh's write_step_summary() and pr-comment.sh render the same
per-finding evidence string from a finding's math_evidence object. This
used to be two independent, hand-copied implementations -- easy to update
one and forget the other, which would let the job summary and the PR
comment silently disagree about what evidence they show for the same
finding. This module is now the one place that logic lives; both scripts
put this file's directory on PYTHONPATH and import it instead.
"""


def format_evidence(me):
    if not me:
        return "n/a"
    method = me.get("method", "")
    if method == "threshold_comparison":
        observed, limit, op = me.get("observed"), me.get("limit"), me.get("operator", "")
        op_symbol = {"gt": ">", "lt": "<"}.get(op, op)
        if observed is not None and limit is not None:
            return f"{observed:.4f} {op_symbol} {limit:.4f}"
    elif method == "shannon_entropy":
        score, threshold = me.get("score"), me.get("threshold")
        if score is not None and threshold is not None:
            return f"score {score:.2f} > {threshold:.2f}"
    return "n/a"
