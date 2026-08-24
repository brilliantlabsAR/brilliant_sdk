"""Packaging compatibility checks for the published brilliant-msg metadata."""

from pathlib import Path
import sys

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name
from packaging.version import Version


def test_python_310_toml_backport_is_declared_in_dev_group():
    """The Python 3.10 fallback must be supplied by the dev dependency group."""
    workspace_manifest_path = Path(__file__).resolve().parents[3] / "pyproject.toml"
    with workspace_manifest_path.open("rb") as manifest:
        workspace = tomllib.load(manifest)

    dev_requirements = [
        Requirement(raw)
        for raw in workspace.get("dependency-groups", {}).get("dev", [])
    ]
    tomli_requirements = [
        requirement
        for requirement in dev_requirements
        if canonicalize_name(requirement.name) == "tomli"
    ]

    assert len(tomli_requirements) == 1, (
        "expected exactly one Python 3.10 TOML backport dependency, found "
        f"{len(tomli_requirements)}"
    )
    tomli_requirement = tomli_requirements[0]

    assert str(tomli_requirement.marker) == 'python_version < "3.11"'
    assert {str(specifier) for specifier in tomli_requirement.specifier} == {
        ">=2.0.1"
    }


def test_source_metadata_has_single_pillow_compatibility_envelope():
    """The checked-in manifest must declare the complete supported Pillow range."""
    manifest_path = Path(__file__).resolve().parents[1] / "pyproject.toml"
    with manifest_path.open("rb") as manifest:
        project = tomllib.load(manifest)["project"]

    requirements = [Requirement(raw) for raw in project.get("dependencies", [])]
    pillow_requirements = [
        requirement
        for requirement in requirements
        if canonicalize_name(requirement.name) == "pillow"
    ]

    assert len(pillow_requirements) == 1, (
        "expected exactly one Pillow dependency, found "
        f"{len(pillow_requirements)}"
    )
    pillow_requirement = pillow_requirements[0]

    assert not pillow_requirement.extras, "Pillow must not request extras"
    assert pillow_requirement.marker is None, "Pillow must not be conditional"
    assert {str(specifier) for specifier in pillow_requirement.specifier} == {
        ">=11.1.0",
        "<13.0.0",
    }

    pillow_specifier = pillow_requirement.specifier

    for version in ("11.1.0", "12.0.0", "12.1.0", "12.999.0"):
        assert Version(version) in pillow_specifier

    assert Version("11.0.9") not in pillow_specifier
    assert Version("13.0.0") not in pillow_specifier
