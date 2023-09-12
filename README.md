# Express Storage System [Solidity]
Universal data/logic partition solution for advanced solidity smart contract systems

Formatted whitepaper: https://docs.google.com/document/d/1FkkZB0z90nDtVZO6p1d8rQIgPsAbWvWk5vsuQb0Fuoc/edit?usp=sharing

Motivation

Segregating contract logic and data is one of the primary ways that smart contract developers introduce modularity and scalability to their contract systems.  However, this design pattern brings added complexity and often demands specially-tailored systems, which creates greater potential for bugs and oversights.  In fact, many custom-built storage solutions are fundamentally similar to others, but must be built from scratch due to the absence of versatile open-source solutions.  Given that these tailored systems are often built with a secondary emphasis, it is not surprising that many useful features and optimizations are often neglected.  The Express Storage System aims to bridge this gap by providing an optimized implementation designed to foster long-term scalability, low-level accessibility, and enhanced efficiency.

![Default System Architecture](https://github.com/wisecameron/ExpressStorageSystem/blob/main/Images/Base%20System%20Architecture.png)

**Basic Overview:**

Contract Structure

Express is composed of a manager contract and a dynamic set of storage contracts.  New storage contract instances can be deployed at any time and are seamlessly included within a shared domain centered around a single manager contract.

Data Structure

Express stores uint[8-256] values in a dynamic bitmap structure.  The deployer passes an array of sizes, which represent the bit length of each tracked value (ie: [8,16,32,8,256,16,32]).   These values are then sorted using simple insertion sort and packed 
into individual uint256 values.  It should be noted that this renders the order of members arbitrary by nature: developers are responsible for defining what each slot represents.  For instance, the above bit structure would be converted to [8, 8, 16, 16, 32, 32, 256] in the live contract, which might disturb the “order” initially understood by the deployer.  Bit packing is automatically handled by the native struct type, though it is not sorted.  

Buildable Structs

In Solidity, struct members are traditionally immutable after deployment: you cannot add or remove data fields.  Express does not support removing data fields, as this would invariably lead to data corruption unless expertly used.  However, new fields can be freely added to the storage contract instance post-deployment.  This makes it much easier to support future updates: developers can just extend their existing systems to track new fields.

MultiMod

Multimod is a distinguishing performance-related feature, allowing multiple fields to be updated with a single store instruction.  In Solidity, storing values in storage is one of the most expensive operations. 
Express uses bit packing, allowing the system to support grouped modification for data members living on the same bit page.  Multimod is more efficient than modify() if at least two values changed are on the same bitmap page, and is still generally cheaper than several modify() calls because it reduces security and initialization-related overhead to only one iteration.  

Extendability

One of the biggest advantages offered by the Express Storage System is the ability to manage all uint-based storage requirements following the mapping-of-struct pattern under one shared domain.  This is accomplished by the ability to deploy and link new StorageSystem instances to the StorageManager after deployment, which can then be seamlessly accessed in the same manner as original members.  For instance, one StorageSystem could describe data about people.  Later, the development team could create a product revolving around automobiles, deploying a new StorageSystem that describes cars.  This new StorageSystem could even track the ID of each car owner (originating from the “person” StorageSystem), creating a link between both instances.  As an aside, the development team could also simply append car-related fields to the “person” StorageSystem instance using the Buildable Structs feature. 

Private Fields

Any abstracted-struct member within a StorageSystem can be marked private.  This bars the value from being viewed through get_value(), but it is still accessible through get_array().  However, get_array() requires administrator-level privileges.

Ownership

One important element to consider is that Express does not manage data ownership beyond allowing administrators to link storage IDs with user addresses.  These links are not used in any way within the storage system or manager logic.  However, the Storage Manager is generally accessed through the logic layer.  This allows developers to employ ownership (which they will most often want to do) functionality without any existing restrictions from the Express system.  

**Security and Scalability:**

![Security Architecture 1](https://github.com/wisecameron/ExpressStorageSystem/blob/main/Images/Security%20Architecture%20Case%201.png)

![Security Architecutre 2](https://github.com/wisecameron/ExpressStorageSystem/blob/main/Images/Security%20Architecture%20Case%202.png)

Providing Secure Low-Level Access
Express provides administrators with full data mutability and visibility, while also empowering them with unique features such as the ability to add new dataset members post-deployment.  With this power comes great potential for both innovation and disaster.  The best design pattern for securely managing this system is to create dedicated logic layers to manage data and permissions within the StorageManager contract.  This allows developers to institute additional verifications specifically tailored for their unique use case.  As with central logic contracts, these security layers should not store mapped data, which would be difficult to port in the event that they need to be updated.  Generally speaking, it is best to keep mapped data in the Express system if you intend to update your logic contracts in the future.  

Example Use Case

Suppose you have developed a smart contract system that empowers external projects to distribute your assets.  You don’t want them to have unfettered access to your low-level data, but you want to provide partnered developers with some advanced permissions to enable more seamless development.  You can create a security layer tailored specifically to their use case, which feeds directly into the Storage Manager contract.  The security layer simply needs to be provided with administrator-level permissions (managed within StorageManager).  From there, you can create and uphold any specifications you see fit, creating a secure system that provides low-level access to external parties without the potential for misuse.  At any time, you are free to update the logic contract or even remove it entirely: it will have no impact on your StorageManager or StorageSystem instances.  

**Code Example: Initialization**

    function initialize()
    external
    {
        //create a dynamic array to store bit structure [necessary to pass into initialize fxn]
        uint256[] memory bitStorage = new uint256[](15);


        //You can also pass this as a function or constructor argument
        uint256[15] memory bits = [uint256(8),8,8,16,64,128,256,256,256,256,256,256,256,256,256];


        //populate array
        for(uint i = 0; i < bits.length; i++)
        {
            bitStorage[i] = bits[i];
        }


        //Get storage handler instance (already deployed)
        StorageHandler manager = StorageHandler(StorageHandlerAddress);


        //initialize storage handler
        manager.initialize(StorageSystemAddress, address(this), vertigoManagerBits, msg.sender);


        //push new value
        manager.push(0);


        //populate
        manager.multimod(0, [9, 7, 8, 11, 2], 0, [75000 * 1e18, 267 * 1e18, 7000 * 1e18, 80, 0])                
    }

**Key Takeaways**
* Express is designed to minimize arbitrary limitations on developer freedom.  The system is very open-ended and does not impose many restrictions to ensure that it is used properly.  Obviously, this low-level access also creates room for error.  Be especially careful when modifying the bit structure of a deployed storage system, as this action is irreversible.  

* The greatest limitation of this system is that it only supports uint storage.  However, one can also store addresses by simply converting as such: uint256(uint160(address)).

* When adding new entries to the system, be sure to first include a push() call.  This ensures that all entries are indexed.

* This contract system has not been audited, I would get it audited before trying to use this in production.  If you do get it audited or audit it yourself, please let me know.  
