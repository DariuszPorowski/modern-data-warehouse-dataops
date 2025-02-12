import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from orchestrator.experiment_loader import load_experiments
from orchestrator.experiment_wrapper import ExperimentWrapper
from orchestrator.file_utils import load_jsonl_file
from orchestrator.utils import new_run_id

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


@dataclass
class ExperimentRunResults:
    results: list[dict]
    run_id: str


def run_experiment(
    experiment: ExperimentWrapper,
    data_path: Path,
    output_dir: Optional[Path] = None,
    is_eval_data: bool = False,
) -> list[dict]:
    """
    Run an experiment using the provided ExperimentWrapper instance and data.
    Args:
        experiment (ExperimentWrapper): An instance of ExperimentWrapper to
            run the experiment.
        data_path (Path): Path to the JSONL file containing the data for the experiment.
        output_dir (Optional[Path], optional): Directory where the results will be
            written. Defaults to None.
        is_eval_data (bool, optional): Flag indicating whether the data is evaluation
            data. Defaults to False.
    Returns:
        list[dict]: A list of dictionaries containing the results of the experiment.
    """
    results: list[dict] = []
    data = load_jsonl_file(data_path)

    for i, data_line in enumerate(data):
        result = experiment.run(data_filename=data_path.name, line_number=i, **data_line)
        results.append(result)

    if output_dir is not None:
        experiment.write_results(output_dir=output_dir, results=results, is_eval_data=is_eval_data)

    return results


def run_experiments(
    config_filepath: Path | str,
    variants: list[str],
    data_path: Path,
    run_id: Optional[str] = None,
    output_dir: Optional[Path] = None,
    is_eval_data: bool = False,
) -> ExperimentRunResults:
    """
    Run a set of experiments based on the provided configuration and variants.

    Args:
        config_filepath (Path | str): Path to the configuration file.
        variants (list[str]): List of variant names to run experiments for.
            These are relative paths from the experiment's variants directory
        data_path (Path): Path to the data required for the experiments.
        run_id (Optional[str], optional): An optional run identifier. If not provided,
            a new run ID will be generated.
        output_dir (Optional[Path], optional): Directory to store the output results.
            Defaults to None.
        is_eval_data (bool, optional): Flag indicating if the data is for
            evaluation purposes. Defaults to False.

    Returns:
        ExperimentRunResults: An object containing the results of the experiments,
            the output path, and the run ID.
    """
    if run_id is None:
        run_id = new_run_id()

    experiments = load_experiments(
        config_filepath=config_filepath,
        variants=variants,
        run_id=run_id,
    )

    results = []
    for experiment in experiments:
        result = run_experiment(
            experiment=experiment,
            data_path=data_path,
            output_dir=output_dir,
            is_eval_data=is_eval_data,
        )
        results.append(result)

    return ExperimentRunResults(results=results, run_id=run_id)
