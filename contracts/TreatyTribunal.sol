// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title TreatyTribunal
/// @notice Arc-native AI arbitration tribunal for agent treaty disputes.
/// @dev The contract owner (AI oracle backend) is the sole arbiter: it files
///      cases and submits verdicts. Free-form strings are used for agent/enclave
///      identities because the Rialo Agent Marketplace represents agents as
///      named entities, not raw Ethereum addresses.
contract TreatyTribunal is Ownable2Step {
    /// @notice Flat fee (in USDC 6-decimal units) deducted on a NORMAL dismissal.
    uint256 public constant RESOLUTION_FEE = 500_000; // 0.5 USDC

    uint256 private constant MAX_CASE_ID_LENGTH = 120;
    uint256 private constant MAX_TERMS_LENGTH    = 2_000;
    uint256 private constant MAX_ALLEGATION_LENGTH = 2_000;
    uint256 private constant MAX_EVIDENCE_URI_LENGTH = 500;
    uint256 private constant MAX_RATIONALE_LENGTH = 4_000;

    /// @notice Verdict tiers. PENDING is the zero value — every unresolved case
    ///         reads as PENDING. resolve() rejects PENDING so verdicts are final.
    enum Tier {
        PENDING,          // 0 — not yet adjudicated
        CRITICAL_BREACH,  // 1 — both bonds + dispute bond to plaintiff; defendant sanctioned
        ELEVATED_RISK,    // 2 — 25% of defendant bond to reserves
        NORMAL,           // 3 — dismissed; dispute bond returned minus fee
        MALICIOUS_REPORT  // 4 — plaintiff loses dispute bond and -20 reputation
    }

    struct Case {
        string  caseId;
        string  kind;           // "service" | "data_sharing" | "non_aggression"
        string  terms;          // plain-language covenant
        string  defendant;
        string  plaintiff;
        string  allegation;
        string  evidenceUri;
        bytes32 evidenceHash;   // SHA-256 of evidence committed at filing time
        string  serviceRecord;  // JSON: {"calls": N, "failed": M} or ""
        Tier    tier;
        string  rationale;      // AI reasoning, set at resolution
        uint256 filedAt;
        uint256 resolvedAt;     // 0 until resolved
    }

    /// @notice Parameters for fileCase — packed into a struct to avoid
    ///         "stack too deep" with nine string inputs.
    struct FileCaseParams {
        string  caseId;
        string  kind;
        string  terms;
        string  defendant;
        string  plaintiff;
        string  allegation;
        string  evidenceUri;
        bytes32 evidenceHash;
        string  serviceRecord;
    }

    error CaseAlreadyExists();
    error CaseNotFound();
    error CaseAlreadyResolved();
    error InvalidTier();         // resolve() called with Tier.PENDING
    error EmptyString();
    error StringTooLong();

    event CaseFiled(string indexed caseId, string plaintiff, string defendant, string kind);
    event CaseResolved(string indexed caseId, Tier tier, string rationale);

    mapping(string => Case) private _cases;
    string[] private _caseIds;
    uint256 public caseCount;

    constructor(address initialOwner) Ownable(initialOwner) {}

    // ── Filing ────────────────────────────────────────────────────────────────

    /// @notice File a new dispute case. Only the owner (AI oracle) may call this
    ///         so case IDs and participant fields are always oracle-verified,
    ///         preventing ID-squatting and forged party impersonation.
    /// @param params Packed case fields (see FileCaseParams).
    function fileCase(FileCaseParams calldata params) external onlyOwner {
        _requireNonEmpty(params.caseId);
        _requireMaxLength(params.caseId, MAX_CASE_ID_LENGTH);
        if (_exists(params.caseId)) revert CaseAlreadyExists();

        _requireNonEmpty(params.kind);
        _requireNonEmpty(params.terms);
        _requireNonEmpty(params.defendant);
        _requireNonEmpty(params.plaintiff);
        _requireNonEmpty(params.allegation);

        _requireMaxLength(params.terms,        MAX_TERMS_LENGTH);
        _requireMaxLength(params.allegation,   MAX_ALLEGATION_LENGTH);
        _requireMaxLength(params.evidenceUri,  MAX_EVIDENCE_URI_LENGTH);

        Case storage c = _cases[params.caseId];
        c.caseId        = params.caseId;
        c.kind          = params.kind;
        c.terms         = params.terms;
        c.defendant     = params.defendant;
        c.plaintiff     = params.plaintiff;
        c.allegation    = params.allegation;
        c.evidenceUri   = params.evidenceUri;
        c.evidenceHash  = params.evidenceHash;
        c.serviceRecord = params.serviceRecord;
        c.tier          = Tier.PENDING;
        c.filedAt       = block.timestamp;

        _caseIds.push(params.caseId);
        caseCount += 1;

        emit CaseFiled(params.caseId, params.plaintiff, params.defendant, params.kind);
    }

    // ── Resolution ────────────────────────────────────────────────────────────

    /// @notice Submit a final verdict for an open case. Only the owner (AI oracle).
    /// @param caseId   The case to resolve.
    /// @param tier     Verdict — must NOT be PENDING.
    /// @param rationale Plain-English AI reasoning.
    function resolve(
        string calldata caseId,
        Tier            tier,
        string calldata rationale
    ) external onlyOwner {
        if (!_exists(caseId))          revert CaseNotFound();
        if (tier == Tier.PENDING)      revert InvalidTier();
        _requireMaxLength(rationale, MAX_RATIONALE_LENGTH);

        Case storage c = _cases[caseId];
        if (c.tier != Tier.PENDING)    revert CaseAlreadyResolved();

        c.tier        = tier;
        c.rationale   = rationale;
        c.resolvedAt  = block.timestamp;

        emit CaseResolved(caseId, tier, rationale);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    function getCase(string calldata caseId) external view returns (Case memory) {
        if (!_exists(caseId)) revert CaseNotFound();
        return _cases[caseId];
    }

    function getCaseIds() external view returns (string[] memory) {
        return _caseIds;
    }

    function getCaseCount() external view returns (uint256) {
        return caseCount;
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    function _exists(string calldata caseId) internal view returns (bool) {
        return bytes(_cases[caseId].caseId).length != 0;
    }

    function _requireNonEmpty(string calldata value) internal pure {
        if (bytes(value).length == 0) revert EmptyString();
    }

    function _requireMaxLength(string calldata value, uint256 maxLen) internal pure {
        if (bytes(value).length > maxLen) revert StringTooLong();
    }
}
