

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b Proxy -o ProxyHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b Proxy -o ProxySquashed.svg
sol2uml storage ../src/contracts,../dependencies -c Proxy -o ProxyStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b MultiAssetARM,LidoARM,EtherFiARM,EthenaARM,OriginARM -o ARMHierarchy.svg

sol2uml ../src/contracts -s -d 0 -b LidoARM -o LidoARMSquashed.svg
sol2uml ../src/contracts -hp -s -d 0 -b LidoARM -o LidoARMPublicSquashed.svg
sol2uml storage ../src/contracts,../dependencies -c LidoARM -o LidoARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -s -d 0 -b OriginARM -o OriginARMSquashed.svg
sol2uml ../src/contracts -hp -s -d 0 -b OriginARM -o OriginARMPublicSquashed.svg
sol2uml storage ../src/contracts,../dependencies -c OriginARM -o OriginARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -s -d 0 -b MultiAssetARM -o MultiAssetARMSquashed.svg
sol2uml ../src/contracts -hp -s -d 0 -b MultiAssetARM -o MultiAssetARMPublicSquashed.svg
sol2uml storage ../src/contracts,../dependencies -c MultiAssetARM -o MultiAssetARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b CapManager -o CapManagerHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b CapManager -o CapManagerSquashed.svg

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b ZapperLidoARM -o ZapperLidoARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b ZapperLidoARM -o ZapperLidoARMSquashed.svg