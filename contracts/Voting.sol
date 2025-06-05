// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Decentralized Voting Contract
/// @notice Manages elections: candidate registration, voter registration, voting, and winner declaration
contract Voting is ReentrancyGuard {
    // --- State Variables ---
    address public superAdmin;
    bool public isPaused;
    string public didRegistryCID;

    uint256 public candidateCount;
    uint256 public voterCount;
    uint256 public totalVotesCast;
    uint256 public votingStart;
    uint256 public votingEnd;
    bool public detailsSet;

    // Tracks current leader to avoid unbounded loops in declareWinner
    uint256 public leadingCandidate;
    uint256 public highestVotes;

    // For resetElection: keep track of all candidate names and who voted
    bytes32[] private candidateHashes;
    address[] private votedVoters;
    address[] private registeredVoters;

    struct Candidate {
        uint256 id;
        string name;
        string slogan;
        uint256 votes;
    }

    struct ElectionDetails {
        string adminName;
        string adminEmail;
        string adminTitle;
        string electionTitle;
        string organizationTitle;
        uint256 maxVotesPerCandidate;
    }

    struct Voter {
        address account;
        string name;
        string phone;
        string did;
        bool isVerified;
        bool isRegistered;
    }

    ElectionDetails public election;
    mapping(address => Voter) private voters;
    mapping(uint256 => Candidate) public candidates;
    mapping(address => bool) public admins;
    mapping(bytes32 => bool) private candidateNameExists;
    mapping(address => bool) public hasVoted;

    // --- Events ---
    event DIDRegistryUpdated(string cid);
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event ElectionDetailsSet(string title, uint256 maxVotes);
    event ElectionStarted(uint256 startTime, uint256 endTime);
    event ElectionEnded(uint256 endTime);
    event CandidateAdded(uint256 indexed id, string name);
    event VoterRegistered(address indexed voter, string name);
    event VoterVerified(address indexed voter);
    event VoteCast(address indexed voter, uint256 indexed candidateId);
    event WinnerDeclared(uint256 indexed candidateId, string name, uint256 votes);
    event ContractPaused(bool paused);
    event ElectionReset();

    // --- Modifiers ---
    modifier onlySuperAdmin() {
        require(msg.sender == superAdmin, "Only super admin");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "Only admin");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "Paused");
        _;
    }

    /// @dev Automatically ends election if time expired
    modifier onlyWhenVotingActive() {
        if (votingEnd != 0 && block.timestamp > votingEnd) {
            endElection();
        }
        require(
            votingStart != 0 &&
            block.timestamp >= votingStart &&
            block.timestamp <= votingEnd,
            "Voting not active"
        );
        _;
    }

    /// @dev Requires election period to be over
    modifier onlyWhenVotingEnded() {
        require(votingEnd != 0 && block.timestamp > votingEnd, "Voting not ended");
        _;
    }

    // --- Constructor ---
    constructor(string memory _didRegistryCID) {
        superAdmin = msg.sender;
        admins[msg.sender] = true;
        didRegistryCID = _didRegistryCID;
        emit DIDRegistryUpdated(_didRegistryCID);
    }

    // --- Admin Functions ---
    function updateDIDRegistry(string memory _cid) external onlySuperAdmin {
        didRegistryCID = _cid;
        emit DIDRegistryUpdated(_cid);
    }

    function addAdmin(address _admin) external onlySuperAdmin {
        require(!admins[_admin], "Already admin");
        admins[_admin] = true;
        emit AdminAdded(_admin);
    }

    function removeAdmin(address _admin) external onlySuperAdmin {
        require(admins[_admin], "Not an admin");
        admins[_admin] = false;
        emit AdminRemoved(_admin);
    }

        /// @notice Resets all per-election state so you can run another election
    function resetElection() external onlyAdmin notPaused {
        require(votingStart == 0 || (votingEnd != 0 && block.timestamp > votingEnd), "Election must be ended");
        votingStart = 0;
        votingEnd   = 0;

        // Clear candidates and name registry
        for (uint256 i = 0; i < candidateCount; i++) {
            delete candidates[i];
        }
        for (uint256 i = 0; i < candidateHashes.length; i++) {
            candidateNameExists[candidateHashes[i]] = false;
        }
        delete candidateHashes;
        candidateCount = 0;

        // Clear vote state
        for (uint256 i = 0; i < votedVoters.length; i++) {
            hasVoted[votedVoters[i]] = false;
        }

        // Clear voter registry
        for (uint i = 0; i < registeredVoters.length; i++) {
            delete voters[registeredVoters[i]];
        }
        delete registeredVoters;
        voterCount = 0;
        delete votedVoters;
        totalVotesCast = 0;

        // Clear election details
        detailsSet = false;
        delete election;

        // Reset leader tracking
        leadingCandidate = 0;
        highestVotes     = 0;

        emit ElectionReset();
    }


    // --- Election Setup ---
    function setElectionDetails(
        string memory _adminName,
        string memory _adminEmail,
        string memory _adminTitle,
        string memory _electionTitle,
        string memory _organizationTitle,
        uint256 _maxVotes
    ) external onlyAdmin notPaused {
        require(bytes(_electionTitle).length > 0, "Title required");
        require(_maxVotes > 0, "Max votes must be > 0");

        election = ElectionDetails({
            adminName: _adminName,
            adminEmail: _adminEmail,
            adminTitle: _adminTitle,
            electionTitle: _electionTitle,
            organizationTitle: _organizationTitle,
            maxVotesPerCandidate: _maxVotes
        });
        detailsSet = true;
        emit ElectionDetailsSet(_electionTitle, _maxVotes);
    }


    // --- Helpers ---
    function getCandidateCount() external view returns (uint256) {
        return candidateCount;
    }

    function getVoter(address _voter) external view returns (Voter memory) {
        return voters[_voter];
    }

    function getVoterTurnout() external view returns (uint256 turnoutPercentage) {
        if (voterCount == 0) return 0;
        return (totalVotesCast * 100) / voterCount;
    }
}
