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
    uint256 public constant REWARD_GDN_AMOUNT = 10 * 10**18; // 10 GDN
    
    // ITEM PRICE
    uint256 public constant PLANT_NFT_COST = 50 * 10**18; // Biaya beli NFT (50 GDN)
    uint256 public constant FERTILIZER_COST = 15 * 10**18; // 15 GDN
    uint256 public constant WATER_COST = 10 * 10**18; // 10 GDN

    // Batas penggunaan per siklus
    uint256 public constant MAX_CYCLE_USE = 2; // Batas penggunaan (2x)
    
    // Interval reset kuota: 2 menit (120 detik)
    uint256 public constant RESET_INTERVAL = 2 minutes; 

    uint256 private _nextPlantId = 1;

    // --- Atribut Tanaman NFT (Data Mutabel) ---
    enum ItemType { FERTILIZER, WATER }

    struct PlantData {
        uint256 progress; // Mengganti plantStatus
        // rewardClaimed dihapus karena progres direset ke 0% setelah klaim
        uint256 lastWaterResetTime; // Waktu terakhir kuota Air direset
        uint256 waterCount;
        uint256 lastFertilizerResetTime; // Waktu terakhir kuota Pupuk direset
        uint256 fertilizerCount;
    }
    mapping(uint256 => PlantData) public plants;
    
    // Event
    event GDNBought(address indexed to, uint256 amount); // Mengganti GDNGiven
    event PlantPurchased(uint256 indexed plantId, address indexed buyer);
    event ProgressUpdated(uint256 indexed plantId, address indexed by, uint256 newProgress);
    event RewardClaimed(uint256 indexed plantId, address indexed owner, uint256 amount);

    // --- Constructor ---
    // Diisi dengan alamat GardenToken
    constructor(address _gdnTokenAddress) ERC721("Lisk Garden Plant", "LGP") Ownable(msg.sender) {
        gdnToken = IERC20(_gdnTokenAddress);
    }

    // --- Fungsi Utama Game (Semua eksternal untuk efisiensi gas) ---

    function buyGDN() external payable {
        require(msg.value == ETH_ENTRY_FEE, "Must pay 0.0001 ETH.");

        address user = msg.sender;
        
        // 1. Berikan GDN (100 GDN) - Memanggil GardenToken.mint
        GardenToken(address(gdnToken)).mint(user, INITIAL_GDN_GIVEAWAY);
        emit GDNBought(user, INITIAL_GDN_GIVEAWAY);
    }
    
    function buyPlantNFT() external {
        address buyer = msg.sender;
        uint256 newPlantId = _nextPlantId;
        
        // 1. Tarik Biaya GDN (50 GDN)
        bool success = gdnToken.transferFrom(buyer, address(this), PLANT_NFT_COST);
        require(success, "GDN transfer failed. Check allowance/balance for 50 GDN.");
        
        // --- BURN IMPLEMENTATION ---
        GardenToken(address(gdnToken)).burn(PLANT_NFT_COST);

        // 2. Mint NFT (ERC-721)
        _safeMint(buyer, newPlantId);
        
        // 3. Set data mutabel (inisialisasi waktu reset 0)
        plants[newPlantId] = PlantData({
            progress: 0,
            lastWaterResetTime: 0, 
            waterCount: 0,
            lastFertilizerResetTime: 0, 
            fertilizerCount: 0
        });

        _nextPlantId++;
        emit PlantPurchased(newPlantId, buyer);
    }

    function useItem(uint256 plantId, ItemType item) external {
        address owner = ownerOf(plantId);
        require(owner == msg.sender, "Must own the plant to use item on it.");
        require(plants[plantId].progress < 100, "Plant is already 100%.");

        uint256 cost;
        uint256 progressIncrease;
        PlantData storage plant = plants[plantId];
        uint256 currentTime = block.timestamp;

        if (item == ItemType.FERTILIZER) {
            cost = FERTILIZER_COST;
            progressIncrease = 20; // +20% progress
            
            // Logika reset kuota 2 menit untuk Pupuk
            if (currentTime >= plant.lastFertilizerResetTime.add(RESET_INTERVAL)) {
                plant.lastFertilizerResetTime = currentTime;
                plant.fertilizerCount = 0;
            }
            require(plant.fertilizerCount < MAX_CYCLE_USE, "Fertilizer limit (2x) reached for this cycle.");
            plant.fertilizerCount = plant.fertilizerCount.add(1);

        } else if (item == ItemType.WATER) {
            cost = WATER_COST;
            progressIncrease = 15; // +15% progress

            // Logika reset kuota 2 menit untuk Air
            if (currentTime >= plant.lastWaterResetTime.add(RESET_INTERVAL)) {
                plant.lastWaterResetTime = currentTime;
                plant.waterCount = 0;
            }
            require(plant.waterCount < MAX_CYCLE_USE, "Water limit (2x) reached for this cycle.");
            plant.waterCount = plant.waterCount.add(1);

        } else {
            revert("Invalid item type.");
        }

        // 1. Tarik biaya GDN dari pengguna
        bool success = gdnToken.transferFrom(msg.sender, address(this), cost);
        require(success, "GDN transfer failed. Check allowance/balance.");

        // --- BURN IMPLEMENTATION ---
        GardenToken(address(gdnToken)).burn(cost); 
        
        // 2. Update Progress
        plant.progress = plant.progress.add(progressIncrease);
        if (plant.progress > 100) {
            plant.progress = 100;
        }

        emit ProgressUpdated(plantId, msg.sender, plant.progress);
    }

    function careForOtherPlant(uint256 plantId) external {
        address plantOwner = ownerOf(plantId);
        // 1. Memastikan pengguna yang memanggil BUKAN pemilik tanaman.
        require(plantOwner != msg.sender, "Cannot care for your own plant using this function.");
        // 2. Memastikan progress belum 100%.
        require(plants[plantId].progress < 100, "Plant is already 100%.");

        // Penambahan progress yang sangat kecil (+1%)
        uint256 progressIncrease = 1; 

        // 3. Update Progress
        plants[plantId].progress = plants[plantId].progress.add(progressIncrease);
        if (plants[plantId].progress > 100) {
            plants[plantId].progress = 100;
        }

        // Tidak ada biaya GDN untuk bantuan ini (free-to-help)
        emit ProgressUpdated(plantId, msg.sender, plants[plantId].progress);
    }

    function claimReward(uint256 plantId) external {
        address owner = ownerOf(plantId);
        require(owner == msg.sender, "Only plant owner can claim reward.");
        
        // Cek progres minimal
        require(plants[plantId].progress >= 100, "Plant progress must be 100% or more.");
        
        // Memberikan Reward (Mint GDN baru: 10 GDN)
        GardenToken(address(gdnToken)).mint(owner, REWARD_GDN_AMOUNT);

        // Reset progress menjadi 0% agar siklus baru dapat dimulai
        plants[plantId].progress = 0;

        emit RewardClaimed(plantId, owner, REWARD_GDN_AMOUNT);
    }
    
    // --- Fungsi Helper (View) ---
    
    function getPlantData(uint256 plantId) public view returns (
        uint256 progress,
        uint256 waterCountInCycle,
        uint256 fertilizerCountInCycle,
        uint256 waterTimeRemaining, // Waktu tersisa (detik)
        uint256 fertilizerTimeRemaining // Waktu tersisa (detik)
    ) {
        PlantData memory data = plants[plantId];
        uint256 currentTime = block.timestamp;
        
        // Cek reset kuota Air
        uint256 waterCount = data.waterCount;
        waterTimeRemaining = 0; 

        if (currentTime >= data.lastWaterResetTime.add(RESET_INTERVAL)) {
            // Kuota direset jika interval 2 menit terlampaui
            waterCount = 0;
        } else {
            // Hitung sisa waktu hingga reset
            waterTimeRemaining = data.lastWaterResetTime.add(RESET_INTERVAL).sub(currentTime);
        }

        // Cek reset kuota Pupuk
        uint256 fertilizerCount = data.fertilizerCount;
        fertilizerTimeRemaining = 0; 
        
        if (currentTime >= data.lastFertilizerResetTime.add(RESET_INTERVAL)) {
            fertilizerCount = 0;
        } else {
            fertilizerTimeRemaining = data.lastFertilizerResetTime.add(RESET_INTERVAL).sub(currentTime);
        }

        // Assignment hasil akhir
        progress = data.progress; 
        waterCountInCycle = waterCount;
        fertilizerCountInCycle = fertilizerCount;
    }
    
    function withdrawETH() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "ETH withdrawal failed");
    }
}
