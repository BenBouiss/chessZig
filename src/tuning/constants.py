INVALID_VALUE: float = 99999.0

# texel weight section
total_idx = 0

# counts
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

# mobility
mobility_idx = total_idx
total_idx += 1

kingMoveCountScore_idx = total_idx
total_idx += 1

# structure protection
structureProtection_idx = total_idx
total_idx += 1

centerProtection_idx = total_idx
total_idx += 1

# pawn structure
isolatedPawnScore_idx = total_idx
total_idx += 1
stackedPawnScore_idx = total_idx
total_idx += 1
passedPawnScore_idx = total_idx
total_idx += 1

# tempo
tempoChecksScore_idx = total_idx
total_idx += 1
pieceThreatScore_idx = total_idx
total_idx += 1
weakCheckmateScore_idx = total_idx
total_idx += 1

# safety
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

# king proximity
kingProximityScore_idx = total_idx
total_idx += 1

# PSQT
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
    "centerProtectionScore",
    "isolatedPawnScore",
    "stackedPawnScore",
    "passedPawnScore",
    "tempoChecksScore",
    "pieceThreatScore",
    "weakCheckmateScore",
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
