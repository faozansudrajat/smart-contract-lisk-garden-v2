// LiskGardenV2.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GardenToken.sol"; // Import ini penting

contract LiskGardenV2 is ERC721, Ownable {
    using SafeMath for uint256;

    IERC20 public gdnToken; 

    // Harga dan reward (18 desimal)
    uint256 public constant ETH_ENTRY_FEE = 100000000000000; // 0.0001 ETH
    uint256 public constant INITIAL_GDN_GIVEAWAY = 100 * 10**18; // 100 GDN
    uint256 public constant REWARD_GDN_AMOUNT = 150 * 10**18; // 150 GDN
    
    // ITEM PRICE
    uint256 public constant PLANT_NFT_COST = 50 * 10**18; // Biaya beli NFT (50 GDN)
    uint256 public constant FERTILIZER_COST = 15 * 10**18; // 15 GDN (+20%)
    uint256 public constant WATER_COST = 10 * 10**18; // 10 GDN (+15%)

    // Durasi simulasi: 3 menit
    uint256 public constant GAME_DEADLINE = 10 minutes;

    uint256 private _nextPlantId = 1;
    mapping(address => bool) public hasPaidEntryFee;

    // --- Atribut Tanaman NFT (Data Mutabel) ---
    enum ItemType { FERTILIZER, WATER }

    struct PlantData {
        uint256 plantStatus;
        uint256 deadline;
        bool rewardClaimed;
    }
    mapping(uint256 => PlantData) public plants;
    
    // Event
    event GDNGiven(address indexed to, uint256 amount);
    event PlantPurchased(uint256 indexed plantId, address indexed buyer, uint256 deadline);
    event StatusUpdated(uint256 indexed plantId, address indexed by, uint256 newStatus);
    event RewardClaimed(uint256 indexed plantId, address indexed owner, uint256 amount);

    // --- Constructor ---
    // Diisi dengan alamat GardenToken
    constructor(address _gdnTokenAddress) ERC721("Lisk Garden Plant", "LGP") Ownable(msg.sender) {
        gdnToken = IERC20(_gdnTokenAddress);
    }

    // --- Fungsi Utama Game ---

    function startJourney() public payable {
        require(msg.value == ETH_ENTRY_FEE, "Must pay 0.0001 ETH entry fee.");
        require(!hasPaidEntryFee[msg.sender], "Entry fee already paid.");

        address user = msg.sender;
        
        // 1. Berikan GDN Awal (100 GDN) - Memanggil GardenToken.mint
        GardenToken(address(gdnToken)).mint(user, INITIAL_GDN_GIVEAWAY);

        hasPaidEntryFee[user] = true;
        emit GDNGiven(user, INITIAL_GDN_GIVEAWAY);
    }
    
    function buyPlantNFT() public {
        address buyer = msg.sender;
        uint256 newPlantId = _nextPlantId;
        
        // 1. Tarik Biaya GDN (50 GDN)
        bool success = gdnToken.transferFrom(buyer, address(this), PLANT_NFT_COST);
        require(success, "GDN transfer failed. Check allowance/balance for 50 GDN.");
        
        // --- BURN IMPLEMENTATION ---
        GardenToken(address(gdnToken)).burn(PLANT_NFT_COST);

        // 2. Mint NFT (ERC-721)
        _safeMint(buyer, newPlantId);
        
        // 3. Set data mutabel
        plants[newPlantId] = PlantData({
            plantStatus: 0,
            deadline: block.timestamp + GAME_DEADLINE,
            rewardClaimed: false
        });

        _nextPlantId++;
        emit PlantPurchased(newPlantId, buyer, plants[newPlantId].deadline);
    }

    function useItem(uint256 plantId, ItemType item) public {
        address owner = ownerOf(plantId);
        require(owner == msg.sender, "Must own the plant to use item on it.");
        require(plants[plantId].plantStatus < 100, "Plant is already 100%.");
        require(block.timestamp < plants[plantId].deadline, "Plant is past its deadline.");

        uint256 cost;
        uint256 statusIncrease;

        if (item == ItemType.FERTILIZER) {
            cost = FERTILIZER_COST;
            statusIncrease = 30;
        } else if (item == ItemType.WATER) {
            cost = WATER_COST;
            statusIncrease = 20;
        } else {
            revert("Invalid item type.");
        }

        // 1. Tarik biaya GDN dari pengguna
        bool success = gdnToken.transferFrom(msg.sender, address(this), cost);
        require(success, "GDN transfer failed. Check allowance/balance.");

        // --- BURN IMPLEMENTATION ---
        GardenToken(address(gdnToken)).burn(cost); 
        
        // 2. Update Status Perawatan
        plants[plantId].plantStatus = plants[plantId].plantStatus.add(statusIncrease);
        if (plants[plantId].plantStatus > 100) {
            plants[plantId].plantStatus = 100;
        }

        emit StatusUpdated(plantId, msg.sender, plants[plantId].plantStatus);
    }

    function careForOtherPlant(uint256 plantId) public {
        address plantOwner = ownerOf(plantId);
        require(plantOwner != msg.sender, "Cannot care for your own plant using this function.");
        require(plants[plantId].plantStatus < 100, "Plant is already 100%.");
        require(block.timestamp < plants[plantId].deadline, "Plant is past its deadline.");

        plants[plantId].plantStatus = plants[plantId].plantStatus.add(5);
        if (plants[plantId].plantStatus > 100) {
            plants[plantId].plantStatus = 100;
        }

        emit StatusUpdated(plantId, msg.sender, plants[plantId].plantStatus);
    }

    function claimReward(uint256 plantId) public {
        address owner = ownerOf(plantId);
        require(owner == msg.sender, "Only plant owner can claim reward.");
        require(plants[plantId].rewardClaimed == false, "Reward already claimed.");
        require(plants[plantId].plantStatus >= 100, "Plant status must be 100%.");
        
        require(block.timestamp <= plants[plantId].deadline, "Deadline has passed. No reward.");

        plants[plantId].rewardClaimed = true;
        // Memberikan Reward (Mint GDN baru)
        GardenToken(address(gdnToken)).mint(owner, REWARD_GDN_AMOUNT);

        emit RewardClaimed(plantId, owner, REWARD_GDN_AMOUNT);
    }
    
    // --- Fungsi Helper ---
    function getPlantData(uint256 plantId) public view returns (
        uint256 status,
        uint256 deadline,
        bool claimed
    ) {
        PlantData memory data = plants[plantId];
        return (data.plantStatus, data.deadline, data.rewardClaimed);
    }
    
    function withdrawETH() public onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "ETH withdrawal failed");
    }
}
