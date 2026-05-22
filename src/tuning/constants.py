INVALID_VALUE: float = 99999.0

# texel weight section
total_idx = 0

countPawn_idx = total_idx
total_idx += 1
countKnight_idx = total_idx
total_idx += 1
countBishop_idx = total_idx
total_idx += 1
countRook_idx = total_idx
total_idx += 1
countQueen_idx = total_idx
total_idx += 1

mobility_idx = total_idx
total_idx += 1

kingMoveCountScore_idx = total_idx
total_idx += 1

structureProtection_idx = total_idx
total_idx += 1

isolatedPawnScore_idx = total_idx
total_idx += 1
stackedPawnScore_idx = total_idx
total_idx += 1
passedPawnScore_idx = total_idx
total_idx += 1

tempoChecksScore_idx = total_idx
total_idx += 1

# not used
safetyPawn_idx = total_idx
total_idx += 1
safetyKnight_idx = total_idx
total_idx += 1
safetyBishop_idx = total_idx
total_idx += 1
safetyRook_idx = total_idx
total_idx += 1
safetyQueen_idx = total_idx
total_idx += 1

kingProximityScore_idx = total_idx
total_idx += 1

PSQT_Pawn_idx = total_idx
total_idx += 64
PSQT_Bishop_idx = total_idx
total_idx += 64
PSQT_Knight_idx = total_idx
total_idx += 64
PSQT_Rook_idx = total_idx
total_idx += 64
PSQT_Queen_idx = total_idx
total_idx += 64
PSQT_King_idx = total_idx
total_idx += 64


strWeightNames = [
    "pawnCountScore",
    "bishopCountScore",
    "knightCountScore",
    "rookCountScore",
    "queenCountScore",
    "mobilityScore",
    "mobilityKingScore",
    "structureProtectionScore",
    "isolatedPawnScore",
    "stackedPawnScore",
    "passedPawnScore",
    "tempoChecksScore",
    "safetyPawn",
    "safetyKnight",
    "safetyBishop",
    "safetyRook",
    "safetyQueen",
    "kingProximityScore",
]

allIndexes = list(range(countPawn_idx, kingProximityScore_idx + 1))
allIndexes.extend(
    [
        PSQT_Pawn_idx,
        PSQT_Bishop_idx,
        PSQT_Knight_idx,
        PSQT_Rook_idx,
        PSQT_Queen_idx,
        PSQT_King_idx,
    ]
)

strPQSTNames = [
    "pawnPSQT",
    "bishopPSQT",
    "knightPSQT",
    "rookPSQT",
    "queenPSQT",
    "kingPSQT",
]
