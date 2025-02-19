from typing import Any

from azure.ai.evaluation import RougeScoreEvaluator, RougeType


class FuzzyMatchEvaluator:
    """
    Calculates the ROUGE score for a given response and ground truth.
    Rouge-L metric is used here which measures the longest common
    subsequence (LCS) between the response and ground truth.

    Args:
        truth_key: The key within the ground truth dictionary that is being evaluated.
    """

    def __init__(self, **kwargs: Any) -> None:
        self.evaluator = RougeScoreEvaluator(rouge_type=RougeType.ROUGE_L)

    def __call__(self, response: list, truth: str, **kwargs: Any):  # type: ignore
        if truth is None:
            if response:
                # we have responses, but truth says we should not have any
                return {"ratio": 0.0}
            else:
                # If truth is none and no citations. The generator did well
                return {"ratio": 1.0}
        elif not response:
            # we have truth but no citations
            return {"ratio": 0.0}

        scores = []
        for r in response:
            excerpt = r.get("excerpt")
            if excerpt is None:
                scores.append(0.0)
            else:
                score_dict = self.evaluator(response=excerpt, ground_truth=truth)
                scores.append(score_dict["rouge_recall"])

        return {"ratio": sum(scores) / len(scores)}
