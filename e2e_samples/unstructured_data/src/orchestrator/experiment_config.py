from copy import deepcopy
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional

from orchestrator.evaluation_config import (
    EvaluationConfig,
    EvaluatorConfigMap,
    EvaluatorLoadConfig,
    merge_eval_config_maps,
)
from orchestrator.file_utils import load_file
from orchestrator.utils import merge_dicts


@dataclass
class VariantConfig:
    """
    VariantConfig is a configuration class for defining experiment variants.
    Attributes:
        name (Optional[str]): The name of the variant.
        parent_variants (list[str]): A list of parent variant names.
        init_args (dict): A dictionary of initialization arguments.
        call_args (dict): A dictionary of arguments for the experiment  __call__ method.
        evaluation (EvaluationConfig): The evaluation configuration for the variant.
        path (Optional[str]): The file path associated with the variant.
        output_container (Optional[str]): The output container for the variant.
        default_output_container (str): The default output container, set to ".".
    """

    name: Optional[str] = None
    parent_variants: list[str] = field(default_factory=list)
    init_args: dict = field(default_factory=dict)
    call_args: dict = field(default_factory=dict)
    evaluation: EvaluationConfig = field(default_factory=EvaluationConfig)
    path: Optional[str] = None
    output_container: Optional[str] = None
    default_output_container = "."


def merge_variant_configs(vc1: VariantConfig, vc2: VariantConfig) -> VariantConfig:
    """
    Merges two VariantConfig objects into one.
    Args:
        vc1 (VariantConfig): The first variant configuration.
        vc2 (VariantConfig): The second variant configuration.
    Returns:
        VariantConfig: A new VariantConfig object that is a combination of vc1 and vc2.
    The merging process includes:
        - vc2 values have precedence.
        - Merging the init_args dictionaries from both configurations.
        - Merging the evaluation configurations from both configurations.
    """
    merged = deepcopy(vc2)
    if merged.name is None and vc1.name is not None:
        merged.name = vc1.name

    if merged.output_container is None and vc1.output_container is not None:
        merged.output_container = vc1.output_container

    if not merged.parent_variants and vc1.parent_variants:
        merged.parent_variants = vc1.parent_variants

    # merge init_args
    merged.init_args = merge_dicts(vc1.init_args, merged.init_args)
    # merge call_args
    merged.call_args = merge_dicts(vc1.call_args, merged.call_args)
    # merge evaluation
    merged_eval = merge_dicts(asdict(vc1.evaluation), asdict(merged.evaluation))
    merged.evaluation = EvaluationConfig(**merged_eval)
    return merged


def load_variant(
    variant_path: Path,
    exp_evaluators: Optional[EvaluatorConfigMap] = None,
) -> VariantConfig:
    """
    Load and merge variant configurations from the specified file path.
    This function loads a variant configuration from a YAML file, merges additional
    configurations if specified, merges evaluator configurations, and recursively
    loads and merges parent variant configurations.
    Args:
        variant_filepath (Path): The path to the variant file to load.
        exp_evaluators (Optional[EvaluatorConfigMap]): The evaluator configs to merge.
    Returns:
        VariantConfig: The loaded and merged variant configuration.
    """

    def load(path: Path, check_has_name: bool = False) -> VariantConfig:
        data = load_file(path)
        if not isinstance(data, dict):
            raise ValueError(f"Invalid variant configuration in {variant_path}")

        evaluation_data = data.get("evaluation", {})
        data["evaluation"] = EvaluationConfig(**evaluation_data)
        data["path"] = variant_path
        variant = VariantConfig(**data)
        # check that the first variant has a name
        if check_has_name and variant.name is None:
            raise ValueError("A loaded variant must have a name")

        # merge evaluators from experiment config
        if exp_evaluators is not None and variant.evaluation is not None:
            variant.evaluation.evaluators = merge_eval_config_maps(exp_evaluators, variant.evaluation.evaluators)

        # merge additional variants
        if variant.parent_variants:
            for p in variant.parent_variants:
                config_path = path.parent.joinpath(p)
                additional_config = load(config_path)
                variant = merge_variant_configs(additional_config, variant)

        return variant

    return load(variant_path, check_has_name=True)


@dataclass
class ExperimentConfig:
    """
    ExperimentConfig class to hold configuration details for an experiment.
    Attributes:
        name (str): The name of the experiment.
        module (str): The module where the experiment class is located.
        class_name (str): The name of the experiment class.
        evaluators (dict[str, EvaluatorLoadConfig]): A dictionary of evaluator
            configurations, default is None.
        variants_dir (str): The realative directory where variant configurations are
            stored, default is "./variants".
    """

    name: str
    module: str
    class_name: str
    evaluators: dict[str, EvaluatorLoadConfig] = field(default_factory=dict)
    variants_dir: str = "./variants"


def load_exp_config(path: Path) -> ExperimentConfig:
    exp_config_data = load_file(path)
    if not isinstance(exp_config_data, dict):
        raise ValueError(f"Invalid experiment configuration in {path}")
    return ExperimentConfig(**exp_config_data)
