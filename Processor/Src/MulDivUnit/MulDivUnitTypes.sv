package MulDivUnitTypes;

import BasicTypes::*;
import MemoryMapTypes::*;
import ActiveListIndexTypes::*;
import LoadStoreUnitTypes::*;


typedef struct packed { // MulDivAcquireData
    ActiveListIndexPath    activeListPtr;
    // LoadQueueIndexPath     loadQueueRecoveryPtr;
    // StoreQueueIndexPath    storeQueueRecoveryPtr;
    // PC_Path                pc;
    OpDst                  opDst;
} MulDivAcquireData;

endpackage