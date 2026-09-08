#!/usr/bin/env python3
"""Generate the empty suggestion seed with coremltools==9.0; no user data needed."""
from pathlib import Path
from coremltools.models.nearest_neighbors import KNearestNeighborsClassifierBuilder
from coremltools.models.utils import save_spec

root = Path(__file__).resolve().parent.parent
destinations = [root / "scripts/fixtures/LauncherSuggestions.mlmodel",
                root / "DeeDock/Resources/LauncherSuggestions.mlmodel"]
builder = KNearestNeighborsClassifierBuilder(
    input_name="context", output_name="appIdentity", number_of_dimensions=256,
    default_class_label="__no_suggestion__", number_of_neighbors=15,
    weighting_scheme="inverse_distance", index_type="linear",
)
builder.description = "Empty on-device app suggestion classifier. Feature schema version 1."
for destination in destinations:
    destination.parent.mkdir(parents=True, exist_ok=True)
    save_spec(builder.spec, str(destination))
    print(destination)
