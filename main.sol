// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Pixel pit-stop ledger — quarter stacks, couch co-op pings, and neon banter hashes.
 * Saloon barrels stay escrowed until hosts draw; the guild kitty is the only sweep lane
 * for the sovereign. Off-chain clients render chorus text; here we keep sigils and seats.
 */

library HfcBitfield {
    uint8 internal constant LOCK_LOBBY = 0x01;
    uint8 internal constant DIM_LIGHTS = 0x02;
    uint8 internal constant VIP_ROPE = 0x04;
    uint8 internal constant AFK_BEACON = 0x08;

    function has(uint8 mask, uint8 flag) internal pure returns (bool) {
        return (mask & flag) != 0;
    }

    function flip(uint8 mask, uint8 flag) internal pure returns (uint8) {
        return mask ^ flag;
    }

    function with(uint8 mask, uint8 flag) internal pure returns (uint8) {
        return mask | flag;
    }

    function without(uint8 mask, uint8 flag) internal pure returns (uint8) {
        return mask & ~flag;
    }

    function onlyFlags(uint8 mask, uint8 allowed) internal pure returns (bool) {
        return (mask | allowed) == allowed;
    }
}

library HfcDice {
    function rollMix(bytes32 salt, address who, uint256 blk, uint256 nonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(salt, who, blk, nonce, address(this))));
    }

    function band4(uint256 mix) internal pure returns (uint8) {
        return uint8(mix % 4);
    }

    function band16(uint256 mix) internal pure returns (uint8) {
        return uint8(mix % 16);
    }

    function band64(uint256 mix) internal pure returns (uint8) {
        return uint8(mix % 64);
    }

    function auraTint(uint256 mix) internal pure returns (uint24 rgb) {
        rgb = uint24(mix & 0xFFFFFF);
    }

    function streakGate(uint256 mix, uint8 need) internal pure returns (bool) {
        return uint8(mix % 100) < need;
    }
}

library HfcTxt {
    uint256 internal constant MAX_CHORUS = 360;
    uint256 internal constant MAX_SLUG_LEN = 48;
    uint256 internal constant MAX_EMOTE_KEY = 24;

    function lenOk(string calldata s, uint256 cap) internal pure returns (bool) {
        return bytes(s).length <= cap;
    }

    function lenOf(string memory s) internal pure returns (uint256) {
        return bytes(s).length;
    }
}

contract HellFireClub {
    error HfcGateDenied();
    error HfcSaloonUnknown(uint256 id);
    error HfcSaloonSealed(uint256 id);
    error HfcCouchOverflow(uint256 cap, uint256 next);
    error HfcCouchVacant();
    error HfcAlreadySeated();
    error HfcChorusTooWide(uint256 have, uint256 cap);
    error HfcSlugAwkward(uint256 have, uint256 cap);
    error HfcSigilZero();
    error HfcTipTooThin(uint256 got, uint256 need);
    error HfcBarrelEmpty();
    error HfcBarrelShort(uint256 have, uint256 ask);
    error HfcBarrelCeiling(uint96 next, uint96 cap);
    error HfcShoutCooldown(uint64 readyAt);
    error HfcGlobally86d(address who);
    error HfcClipOn(address who, uint256 saloon);
    error HfcHostOnly();
    error HfcCaptainOrCurator();
    error HfcKittyDry();
    error HfcForwardFail(address to, uint256 wei_);
    error HfcReverbTrap();
    error HfcInviteStale(uint64 expiresAt);
    error HfcInviteMismatch(address expect, address got);
    error HfcPartyFull(uint256 cap);
    error HfcPartyUnknown(uint256 pid);
    error HfcRankOutOfBand(uint8 r);
    error HfcVibeOutOfBand(uint8 v);
    error HfcCapOutOfBand(uint32 c);
    error HfcSaloonLimit(uint256 have, uint256 max_);
    error HfcWhisperUnknown(uint256 wid);
    error HfcSelfPing();
    error HfcDuplicateSlug(bytes32 slug);
    error HfcWatchlistClash(address a, address b);
    error HfcLedgerSkew(uint256 bal, uint256 barrels, uint256 kitty);
    error HfcEmoteSpam(uint64 readyAt);
    error HfcReactionCap(uint8 lane);
    error HfcDuelSelf();
    error HfcSpotlightUnknown(uint256 sid);
    error HfcBountyThin(uint256 got, uint256 need);
    error HfcBountyStillLocked(uint64 unlockAt);
    error HfcBountyVaultEmpty();

    event SaloonSpawned(
        uint256 indexed saloonId,
        address indexed host,
        bytes32 slug,
        uint32 couchCap,
        uint8 vibe,
        uint64 whenTs
    );
    event SaloonSealed(uint256 indexed saloonId, address indexed by);
    event CouchClaimed(uint256 indexed saloonId, address indexed guest, uint8 guildRank, uint64 whenTs);
    event CouchVacated(uint256 indexed saloonId, address indexed guest, uint64 whenTs);
    event ChorusPosted(
        uint256 indexed whisperId,
        uint256 indexed saloonId,
        address indexed bard,
        bytes32 sigil,
        uint8 tintBand,
        uint64 whenTs
    );
    event NickTagged(address indexed who, bytes32 nickDigest);
    event TipSplashed(uint256 indexed saloonId, address indexed from, uint256 weiAmt, uint64 whenTs);
    event BarrelWithdrawn(uint256 indexed saloonId, address indexed host, uint256 weiAmt, uint64 whenTs);
    event GuildKittyFed(address indexed from, uint256 weiAmt, uint64 whenTs);
    event GuildKittySwept(address indexed to, uint256 weiAmt, uint64 whenTs);
    event ClipToggled(uint256 indexed saloonId, address indexed target, bool clipped, address indexed by);
    event BanHammer(address indexed target, bool banned, address indexed by);
    event WatchCaptainRotated(address indexed prior, address indexed next, address indexed by);
    event GuildVaultRotated(address indexed prior, address indexed next, address indexed by);
    event PartyFounded(uint256 indexed partyId, address indexed leader, uint32 cap, uint64 whenTs);
    event PartyJoined(uint256 indexed partyId, address indexed who, uint64 whenTs);
    event PartyLeft(uint256 indexed partyId, address indexed who, uint64 whenTs);
    event PartyDisbanded(uint256 indexed partyId, address indexed by, uint64 whenTs);
    event InviteMinted(bytes32 indexed inviteHash, uint256 indexed saloonId, address indexed guest, uint64 expiresAt);
    event LobbyFlagSet(uint256 indexed saloonId, uint8 prior, uint8 next, address indexed by);
    event PingEcho(address indexed from, address indexed to, bytes32 nonce, uint64 whenTs);
    event EmoteSpark(
        uint256 indexed saloonId,
        address indexed who,
        bytes32 emoteKey,
        uint8 lane,
        uint64 whenTs
    );
    event ReactionStamped(uint256 indexed saloonId, uint256 indexed whisperId, address indexed who, uint8 lane);
    event SpotlightPinned(uint256 indexed saloonId, uint256 indexed whisperId, address indexed by);
    event CouchDuelLogged(uint256 indexed saloonId, address indexed a, address indexed b, bytes32 salt, uint8 roll);
    event BountyPosted(uint256 indexed saloonId, address indexed host, uint256 weiAmt, uint64 unlockAt);
    event BountyClaimed(uint256 indexed saloonId, address indexed host, uint256 weiAmt, uint64 whenTs);

    struct Saloon {
        bytes32 slug;
        address host;
        uint32 couchCap;
        uint32 couchTaken;
        uint64 bornTs;
        uint8 vibeCode;
        uint8 lobbyFlags;
        uint96 tipBarrel;
        uint32 whisperCount;
        uint256 spotlightWhisperId;
        uint64 bountyUnlockTs;
        uint96 bountyWei;
        bool sealed;
    }

    struct CouchSeat {
        uint64 joinedTs;
        uint8 guildRank;
        bool clip;
    }

    struct Whisper {
        address bard;
        uint256 saloonId;
        uint64 whenTs;
        bytes32 sigil;
        string chorus;
    }

    struct PartyBus {
        address leader;
        uint32 cap;
        uint32 riders;
        uint64 bornTs;
        bool disbanded;
    }

    address public immutable emberSovereign;
    address public guildTreasury;
    address public shiftCaptain;

    uint256 private _pulse;

    uint256 public nextSaloonId;
    uint256 public nextWhisperId;
    uint256 public nextPartyId;

    uint256 public totalBarrelWeiLocked;
    uint256 public bountyWeiLocked;
    uint256 public guildKittyWei;
    uint256 public totalBarrelOutWei;
    uint256 public totalKittyOutWei;
    uint256 public shoutCount;
    uint256 public emoteCount;

    uint64 public shoutCooldownSec;
    uint64 public emoteCooldownSec;
    uint256 public minTipWei;
    uint256 public maxLounges;
    uint256 public maxWhisperReactions;

    mapping(uint256 => Saloon) private _saloon;
    mapping(uint256 => mapping(address => CouchSeat)) private _seat;
    mapping(uint256 => Whisper) private _whisper;
    mapping(uint256 => PartyBus) private _party;
    mapping(bytes32 => bool) private _slugTaken;
    mapping(address => bytes32) public nickOf;
    mapping(address => uint64) private _lastShoutAt;
    mapping(address => uint64) private _lastEmoteAt;
    mapping(address => bool) public globallyBanned;
    mapping(uint256 => mapping(address => bool)) public loungeClipped;
    mapping(address => uint256) public partyOf;
    mapping(bytes32 => uint64) private _inviteExpiry;
    mapping(uint256 => mapping(uint256 => mapping(address => uint8))) private _whisperCheer;

    modifier nonReentrant() {
        if (_pulse == 2) revert HfcReverbTrap();
        _pulse = 2;
        _;
        _pulse = 1;
    }

    modifier onlySovereign() {
        if (msg.sender != emberSovereign) revert HfcGateDenied();
        _;
    }

    modifier sovereignOrCaptain() {
        if (msg.sender != emberSovereign && msg.sender != shiftCaptain) revert HfcCaptainOrCurator();
        _;
    }

    constructor() {
        address deployer = msg.sender;
        emberSovereign = deployer;
        guildTreasury = deployer;
        shiftCaptain = deployer;
        if (deployer == address(0)) {
            revert HfcWatchlistClash(emberSovereign, guildTreasury);
        }
        nextSaloonId = 1;
        nextWhisperId = 1;
        nextPartyId = 1;
        shoutCooldownSec = 11;
        emoteCooldownSec = 4;
        minTipWei = 1;
        maxLounges = 2048;
        maxWhisperReactions = 1024;
        _pulse = 1;
    }

    receive() external payable {
        guildKittyWei += msg.value;
        emit GuildKittyFed(msg.sender, msg.value, uint64(block.timestamp));
    }

    fallback() external payable {
        guildKittyWei += msg.value;
        emit GuildKittyFed(msg.sender, msg.value, uint64(block.timestamp));
    }

    function versionTag() external pure returns (bytes32) {
        return keccak256("HellFireClub/pixel-pitstop/4.2.7");
    }

    function setShoutCooldown(uint64 sec) external onlySovereign {
        shoutCooldownSec = sec;
    }

    function setEmoteCooldown(uint64 sec) external onlySovereign {
        emoteCooldownSec = sec;
    }

    function setMinTipWei(uint256 wei_) external onlySovereign {
        minTipWei = wei_;
    }

    function setMaxLounges(uint256 cap_) external onlySovereign {
        maxLounges = cap_;
    }

    function setMaxWhisperReactions(uint256 cap_) external onlySovereign {
        maxWhisperReactions = cap_;
    }
