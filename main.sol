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

    function rotateShiftCaptain(address next) external onlySovereign {
        if (next == address(0)) revert HfcForwardFail(next, 0);
        address prior = shiftCaptain;
        shiftCaptain = next;
        emit WatchCaptainRotated(prior, next, msg.sender);
    }

    function rotateGuildTreasury(address next) external onlySovereign {
        if (next == address(0)) revert HfcForwardFail(next, 0);
        address prior = guildTreasury;
        guildTreasury = next;
        emit GuildVaultRotated(prior, next, msg.sender);
    }

    function _requireSaloon(uint256 saloonId) internal view returns (Saloon storage s) {
        s = _saloon[saloonId];
        if (s.host == address(0)) revert HfcSaloonUnknown(saloonId);
    }

    function _balanceInvariant() internal view {
        uint256 bal = address(this).balance;
        uint256 tracked = totalBarrelWeiLocked + guildKittyWei + bountyWeiLocked;
        if (bal < tracked) {
            revert HfcLedgerSkew(bal, totalBarrelWeiLocked, guildKittyWei);
        }
    }

    function saloonSummary(uint256 saloonId)
        external
        view
        returns (
            bytes32 slug_,
            address host_,
            uint32 couchCap_,
            uint32 couchTaken_,
            uint64 bornTs_,
            uint8 vibeCode_,
            uint8 lobbyFlags_,
            uint96 tipBarrel_,
            uint32 whisperCt_,
            uint256 spotlight_,
            uint64 bountyUnlock_,
            uint96 bountyWei_,
            bool sealed_
        )
    {
        Saloon memory s = _saloon[saloonId];
        if (s.host == address(0)) revert HfcSaloonUnknown(saloonId);
        slug_ = s.slug;
        host_ = s.host;
        couchCap_ = s.couchCap;
        couchTaken_ = s.couchTaken;
        bornTs_ = s.bornTs;
        vibeCode_ = s.vibeCode;
        lobbyFlags_ = s.lobbyFlags;
        tipBarrel_ = s.tipBarrel;
        whisperCt_ = s.whisperCount;
        spotlight_ = s.spotlightWhisperId;
        bountyUnlock_ = s.bountyUnlockTs;
        bountyWei_ = s.bountyWei;
        sealed_ = s.sealed;
    }

    function spawnSaloon(bytes32 slug, uint32 couchCap, uint8 vibe, uint8 lobbyFlags)
        external
        returns (uint256 saloonId)
    {
        if (nextSaloonId > maxLounges) revert HfcSaloonLimit(nextSaloonId, maxLounges);
        if (slug == bytes32(0)) revert HfcSigilZero();
        if (_slugTaken[slug]) revert HfcDuplicateSlug(slug);
        if (couchCap == 0 || couchCap > 10_000) revert HfcCapOutOfBand(couchCap);
        if (vibe > 31) revert HfcVibeOutOfBand(vibe);
        if (!HfcBitfield.onlyFlags(lobbyFlags, 0x0F)) revert HfcVibeOutOfBand(lobbyFlags);

        saloonId = nextSaloonId++;
        _slugTaken[slug] = true;
        _saloon[saloonId] = Saloon({
            slug: slug,
            host: msg.sender,
            couchCap: couchCap,
            couchTaken: 0,
            bornTs: uint64(block.timestamp),
            vibeCode: vibe,
            lobbyFlags: lobbyFlags,
            tipBarrel: 0,
            whisperCount: 0,
            spotlightWhisperId: 0,
            bountyUnlockTs: 0,
            bountyWei: 0,
            sealed: false
        });

        emit SaloonSpawned(saloonId, msg.sender, slug, couchCap, vibe, uint64(block.timestamp));
    }

    function sealSaloon(uint256 saloonId) external {
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host && msg.sender != emberSovereign && msg.sender != shiftCaptain) revert HfcHostOnly();
        if (s.sealed) revert HfcSaloonSealed(saloonId);
        s.sealed = true;
        emit SaloonSealed(saloonId, msg.sender);
    }

    function setLobbyFlags(uint256 saloonId, uint8 flags) external {
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host && msg.sender != emberSovereign) revert HfcHostOnly();
        if (!HfcBitfield.onlyFlags(flags, 0x0F)) revert HfcVibeOutOfBand(flags);
        uint8 prior = s.lobbyFlags;
        s.lobbyFlags = flags;
        emit LobbyFlagSet(saloonId, prior, flags, msg.sender);
    }

    function claimCouch(uint256 saloonId, uint8 guildRank) external {
        if (globallyBanned[msg.sender]) revert HfcGlobally86d(msg.sender);
        Saloon storage s = _requireSaloon(saloonId);
        if (s.sealed) revert HfcSaloonSealed(saloonId);
        if (HfcBitfield.has(s.lobbyFlags, HfcBitfield.LOCK_LOBBY) && msg.sender != s.host && msg.sender != emberSovereign) {
            revert HfcSaloonSealed(saloonId);
        }
        if (loungeClipped[saloonId][msg.sender]) revert HfcClipOn(msg.sender, saloonId);
        if (guildRank > 7) revert HfcRankOutOfBand(guildRank);
        CouchSeat storage seat = _seat[saloonId][msg.sender];
        if (seat.joinedTs != 0) revert HfcAlreadySeated();
        uint256 nextTaken = uint256(s.couchTaken) + 1;
        if (nextTaken > uint256(s.couchCap)) revert HfcCouchOverflow(s.couchCap, uint32(nextTaken));

        s.couchTaken = uint32(nextTaken);
        seat.joinedTs = uint64(block.timestamp);
        seat.guildRank = guildRank;
        seat.clip = false;

        emit CouchClaimed(saloonId, msg.sender, guildRank, uint64(block.timestamp));
    }

    function leaveCouch(uint256 saloonId) external {
        Saloon storage s = _requireSaloon(saloonId);
        CouchSeat storage seat = _seat[saloonId][msg.sender];
        if (seat.joinedTs == 0) revert HfcCouchVacant();
        if (s.couchTaken == 0) revert HfcCouchVacant();
        unchecked {
            s.couchTaken -= 1;
        }
        delete _seat[saloonId][msg.sender];
        emit CouchVacated(saloonId, msg.sender, uint64(block.timestamp));
    }

    function tagNick(bytes32 nickDigest) external {
        nickOf[msg.sender] = nickDigest;
        emit NickTagged(msg.sender, nickDigest);
    }

    function postChorus(uint256 saloonId, bytes32 sigil, string calldata chorus) external returns (uint256 whisperId) {
        if (globallyBanned[msg.sender]) revert HfcGlobally86d(msg.sender);
        if (sigil == bytes32(0)) revert HfcSigilZero();
        if (!HfcTxt.lenOk(chorus, HfcTxt.MAX_CHORUS)) revert HfcChorusTooWide(bytes(chorus).length, HfcTxt.MAX_CHORUS);
        Saloon storage s = _requireSaloon(saloonId);
        if (s.sealed) revert HfcSaloonSealed(saloonId);
        if (loungeClipped[saloonId][msg.sender]) revert HfcClipOn(msg.sender, saloonId);

        uint64 last = _lastShoutAt[msg.sender];
        uint64 ready = last + shoutCooldownSec;
        if (last != 0 && block.timestamp < ready) revert HfcShoutCooldown(ready);

        whisperId = nextWhisperId++;
        _whisper[whisperId] = Whisper({
            bard: msg.sender,
            saloonId: saloonId,
            whenTs: uint64(block.timestamp),
            sigil: sigil,
            chorus: chorus
        });
        unchecked {
            s.whisperCount += 1;
        }
        shoutCount += 1;
        _lastShoutAt[msg.sender] = uint64(block.timestamp);

        uint256 mix = HfcDice.rollMix(sigil, msg.sender, block.number, whisperId);
        emit ChorusPosted(whisperId, saloonId, msg.sender, sigil, HfcDice.band16(mix), uint64(block.timestamp));
    }

    function tipBarrel(uint256 saloonId) external payable nonReentrant {
        if (msg.value < minTipWei) revert HfcTipTooThin(msg.value, minTipWei);
        Saloon storage s = _requireSaloon(saloonId);
        if (s.sealed) revert HfcSaloonSealed(saloonId);
        uint256 nextBarrel = uint256(s.tipBarrel) + msg.value;
        if (nextBarrel > type(uint96).max) revert HfcBarrelCeiling(uint96(nextBarrel), type(uint96).max);
        unchecked {
            s.tipBarrel = uint96(nextBarrel);
        }
        totalBarrelWeiLocked += msg.value;
        _balanceInvariant();
        emit TipSplashed(saloonId, msg.sender, msg.value, uint64(block.timestamp));
    }

    function hostDrawBarrel(uint256 saloonId, uint256 weiAsk) external nonReentrant {
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host) revert HfcHostOnly();
        uint256 have = uint256(s.tipBarrel);
        if (have == 0) revert HfcBarrelEmpty();
        if (weiAsk == 0 || weiAsk > have) revert HfcBarrelShort(have, weiAsk);
        if (weiAsk > totalBarrelWeiLocked) {
            revert HfcLedgerSkew(address(this).balance, totalBarrelWeiLocked, guildKittyWei);
        }

        unchecked {
            s.tipBarrel -= uint96(weiAsk);
            totalBarrelWeiLocked -= weiAsk;
        }
        totalBarrelOutWei += weiAsk;

        (bool ok,) = payable(msg.sender).call{value: weiAsk}("");
        if (!ok) revert HfcForwardFail(msg.sender, weiAsk);

        emit BarrelWithdrawn(saloonId, msg.sender, weiAsk, uint64(block.timestamp));
    }

    function feedGuildKitty() external payable {
        if (msg.value == 0) revert HfcKittyDry();
        guildKittyWei += msg.value;
        emit GuildKittyFed(msg.sender, msg.value, uint64(block.timestamp));
    }

    function sweepGuildKitty(uint256 weiCap) external nonReentrant onlySovereign {
        if (guildKittyWei == 0) revert HfcKittyDry();
        uint256 pull = weiCap == 0 ? guildKittyWei : weiCap;
        if (pull > guildKittyWei) pull = guildKittyWei;
        uint256 bal = address(this).balance;
        uint256 owedBarrels = totalBarrelWeiLocked;
        uint256 owedBounty = bountyWeiLocked;
        if (bal < owedBarrels + owedBounty + pull) {
            revert HfcLedgerSkew(bal, owedBarrels, guildKittyWei);
        }
        unchecked {
            guildKittyWei -= pull;
        }
        totalKittyOutWei += pull;
        address sink = guildTreasury;
        (bool ok,) = payable(sink).call{value: pull}("");
        if (!ok) revert HfcForwardFail(sink, pull);
        emit GuildKittySwept(sink, pull, uint64(block.timestamp));
    }

    function setClip(uint256 saloonId, address target, bool clipped) external sovereignOrCaptain {
        if (target == address(0)) revert HfcForwardFail(target, 0);
        _requireSaloon(saloonId);
        loungeClipped[saloonId][target] = clipped;
        emit ClipToggled(saloonId, target, clipped, msg.sender);
    }

    function setGlobalBan(address target, bool banned) external sovereignOrCaptain {
        if (target == address(0)) revert HfcForwardFail(target, 0);
        globallyBanned[target] = banned;
        emit BanHammer(target, banned, msg.sender);
    }

    function mintInvite(bytes32 inviteHash, uint256 saloonId, address guest, uint64 expiresAt) external {
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host && msg.sender != emberSovereign) revert HfcHostOnly();
        if (inviteHash == bytes32(0)) revert HfcSigilZero();
        if (guest == address(0)) revert HfcForwardFail(guest, 0);
        if (expiresAt <= block.timestamp) revert HfcInviteStale(expiresAt);
        _inviteExpiry[inviteHash] = expiresAt;
        emit InviteMinted(inviteHash, saloonId, guest, expiresAt);
    }

    function redeemInvite(bytes32 inviteHash, address guest) external {
        uint64 ex = _inviteExpiry[inviteHash];
        if (ex == 0) revert HfcSigilZero();
        if (block.timestamp > ex) revert HfcInviteStale(ex);
        if (guest != msg.sender) revert HfcInviteMismatch(guest, msg.sender);
        delete _inviteExpiry[inviteHash];
    }

    function foundParty(uint32 cap) external returns (uint256 partyId) {
        if (partyOf[msg.sender] != 0) revert HfcAlreadySeated();
        if (cap == 0 || cap > 64) revert HfcCapOutOfBand(cap);
        partyId = nextPartyId++;
        _party[partyId] = PartyBus({
            leader: msg.sender,
            cap: cap,
            riders: 1,
            bornTs: uint64(block.timestamp),
            disbanded: false
        });
        partyOf[msg.sender] = partyId;
        emit PartyFounded(partyId, msg.sender, cap, uint64(block.timestamp));
    }

    function joinParty(uint256 partyId) external {
        PartyBus storage p = _party[partyId];
        if (p.leader == address(0)) revert HfcPartyUnknown(partyId);
        if (p.disbanded) revert HfcPartyUnknown(partyId);
        if (partyOf[msg.sender] != 0) revert HfcAlreadySeated();
        uint256 nextR = uint256(p.riders) + 1;
        if (nextR > uint256(p.cap)) revert HfcPartyFull(p.cap);
        p.riders = uint32(nextR);
        partyOf[msg.sender] = partyId;
        emit PartyJoined(partyId, msg.sender, uint64(block.timestamp));
    }

    function leaveParty(uint256 partyId) external {
        PartyBus storage p = _party[partyId];
        if (p.leader == address(0)) revert HfcPartyUnknown(partyId);
        if (partyOf[msg.sender] != partyId) revert HfcPartyUnknown(partyId);
        if (p.riders == 0) revert HfcCouchVacant();
        unchecked {
            p.riders -= 1;
        }
        delete partyOf[msg.sender];
        emit PartyLeft(partyId, msg.sender, uint64(block.timestamp));
    }

    function disbandParty(uint256 partyId) external {
        PartyBus storage p = _party[partyId];
        if (p.leader == address(0)) revert HfcPartyUnknown(partyId);
        if (msg.sender != p.leader && msg.sender != emberSovereign) revert HfcHostOnly();
        p.disbanded = true;
        emit PartyDisbanded(partyId, msg.sender, uint64(block.timestamp));
    }

    function pingPeer(address to, bytes32 nonce) external {
        if (to == address(0)) revert HfcForwardFail(to, 0);
        if (to == msg.sender) revert HfcSelfPing();
        emit PingEcho(msg.sender, to, nonce, uint64(block.timestamp));
    }

    function sparkEmote(uint256 saloonId, bytes32 emoteKey, uint8 lane) external {
        if (globallyBanned[msg.sender]) revert HfcGlobally86d(msg.sender);
        _requireSaloon(saloonId);
        if (lane > 11) revert HfcReactionCap(lane);
        if (emoteKey == bytes32(0)) revert HfcSigilZero();
        uint64 lastE = _lastEmoteAt[msg.sender];
        uint64 emReady = lastE + emoteCooldownSec;
        if (lastE != 0 && block.timestamp < emReady) revert HfcEmoteSpam(emReady);
        _lastEmoteAt[msg.sender] = uint64(block.timestamp);
        emoteCount += 1;
        emit EmoteSpark(saloonId, msg.sender, emoteKey, lane, uint64(block.timestamp));
    }

    function cheerWhisper(uint256 saloonId, uint256 whisperId, uint8 lane) external {
        if (lane > 7) revert HfcReactionCap(lane);
        _requireSaloon(saloonId);
        Whisper storage w = _whisper[whisperId];
        if (w.bard == address(0)) revert HfcWhisperUnknown(whisperId);
        if (w.saloonId != saloonId) revert HfcWhisperUnknown(whisperId);
        _whisperCheer[saloonId][whisperId][msg.sender] = lane;
        emit ReactionStamped(saloonId, whisperId, msg.sender, lane);
    }

    function pinSpotlight(uint256 saloonId, uint256 whisperId) external {
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host && msg.sender != emberSovereign) revert HfcHostOnly();
        Whisper storage w = _whisper[whisperId];
        if (w.bard == address(0)) revert HfcWhisperUnknown(whisperId);
        if (w.saloonId != saloonId) revert HfcSpotlightUnknown(saloonId);
        s.spotlightWhisperId = whisperId;
        emit SpotlightPinned(saloonId, whisperId, msg.sender);
    }

    function logCouchDuel(uint256 saloonId, address rival, bytes32 salt) external {
        if (rival == address(0)) revert HfcForwardFail(rival, 0);
        if (rival == msg.sender) revert HfcDuelSelf();
        _requireSaloon(saloonId);
        uint256 mix = HfcDice.rollMix(salt, msg.sender, block.number, uint256(uint160(rival)));
        uint8 roll = HfcDice.band64(mix);
        emit CouchDuelLogged(saloonId, msg.sender, rival, salt, roll);
    }

    function postBounty(uint256 saloonId, uint64 unlockAt) external payable nonReentrant {
        if (msg.value == 0) revert HfcBountyThin(msg.value, 1);
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host) revert HfcHostOnly();
        if (unlockAt <= block.timestamp) revert HfcInviteStale(unlockAt);
        uint256 nextB = uint256(s.bountyWei) + msg.value;
        if (nextB > type(uint96).max) revert HfcBarrelCeiling(uint96(nextB), type(uint96).max);
        s.bountyWei = uint96(nextB);
        s.bountyUnlockTs = unlockAt;
        unchecked {
            bountyWeiLocked += msg.value;
        }
        _balanceInvariant();
        emit BountyPosted(saloonId, msg.sender, msg.value, unlockAt);
    }

    function claimBounty(uint256 saloonId) external nonReentrant {
        Saloon storage s = _requireSaloon(saloonId);
        if (msg.sender != s.host) revert HfcHostOnly();
        uint256 amt = uint256(s.bountyWei);
