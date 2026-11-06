#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "netCDF4"]
# ///
"""Build ios/Currents/Resources/Data/tide_constants.bin from the EOT20 ocean tide atlas.

EOT20 (Hart-Davis et al. 2021, CC BY 4.0, https://doi.org/10.17882/79489) gives
amplitude and phase on a 1/8 degree grid. The app only needs the water near a
coast, so this keeps every Nth cell within a band of the land and drops the rest.

    curl -fLO https://www.seanoe.org/data/00683/79489/data/85762.zip
    unzip 85762.zip && unzip ocean_tides.zip
    uv run scripts/build_tide_constants.py ocean_tides

Little-endian layout:
    0   "TIDE"
    4   UInt32 cell count
    8   UInt16 constituent count
    10  UInt16 cells per degree
    12  UInt32 cell keys, sorted: latIndex * (360 * cellsPerDegree) + lonIndex,
        latIndex counted from 90 S, lonIndex from 0 E going east
    ..  Int16 pairs for each cell and constituent, in millimetres:
        amplitude * cos(phase), amplitude * sin(phase)
"""

import argparse
import struct
from pathlib import Path

import netCDF4
import numpy as np

# The order TideEngine reads them in.
CONSTITUENTS = ["M2", "S2", "N2", "K2", "K1", "O1", "P1", "Q1", "2N2", "M4"]
SOURCE_CELLS_PER_DEGREE = 8


def read(directory: Path, name: str):
    with netCDF4.Dataset(directory / f"{name}_ocean_eot20.nc") as nc:
        amplitude = np.ma.filled(nc["amplitude"][:], np.nan)
        phase = np.ma.filled(nc["phase"][:], np.nan)
    # The last column repeats 0 E as 360 E.
    return amplitude[:, :-1], phase[:, :-1]


def near_water_band(water: np.ndarray, radius: int) -> np.ndarray:
    """Water within `radius` source cells of land, wrapping around the globe."""
    land = ~water
    near = land.copy()
    for _ in range(radius):
        grown = near.copy()
        grown[1:, :] |= near[:-1, :]
        grown[:-1, :] |= near[1:, :]
        grown |= np.roll(near, 1, axis=1) | np.roll(near, -1, axis=1)
        near = grown
    return near & water


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("atlas", type=Path, help="folder holding the *_ocean_eot20.nc files")
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).parent.parent / "ios/Currents/Resources/Data/tide_constants.bin")
    parser.add_argument("--cells-per-degree", type=int, default=2, choices=[1, 2, 4, 8])
    parser.add_argument("--band-degrees", type=float, default=2.0, help="how far from land to keep")
    args = parser.parse_args()

    fields = [read(args.atlas, name) for name in CONSTITUENTS]
    water = ~np.isnan(fields[0][0])
    band = near_water_band(water, round(args.band_degrees * SOURCE_CELLS_PER_DEGREE))

    stride = SOURCE_CELLS_PER_DEGREE // args.cells_per_degree
    lat_index, lon_index = np.nonzero(band[::stride, ::stride])
    columns = 360 * args.cells_per_degree
    keys = lat_index.astype(np.uint32) * columns + lon_index.astype(np.uint32)

    values = np.zeros((len(keys), len(CONSTITUENTS), 2), dtype=np.int16)
    for c, (amplitude, phase) in enumerate(fields):
        amp_mm = np.nan_to_num(amplitude[::stride, ::stride][lat_index, lon_index]) * 10
        rad = np.radians(np.nan_to_num(phase[::stride, ::stride][lat_index, lon_index]))
        values[:, c, 0] = np.rint(amp_mm * np.cos(rad)).astype(np.int16)
        values[:, c, 1] = np.rint(amp_mm * np.sin(rad)).astype(np.int16)

    with args.out.open("wb") as out:
        out.write(b"TIDE")
        out.write(struct.pack("<IHH", len(keys), len(CONSTITUENTS), args.cells_per_degree))
        out.write(keys.astype("<u4").tobytes())
        out.write(values.astype("<i2").tobytes())
    print(f"{args.out}: {len(keys)} cells, {args.out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
