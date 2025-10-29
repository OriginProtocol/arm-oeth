

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b Proxy -o ProxyHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b Proxy -o ProxySquashed.svg
sol2uml storage ../src/contracts -c Proxy -o ProxyStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b LidoARM -o LidoARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b LidoARM -o LidoARMSquashed.svg
sol2uml ../src/contracts -hp -s -d 0 -b LidoARM -o LidoARMPublicSquashed.svg
sol2uml storage ../src/contracts,../lib -c LidoARM -o LidoARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b OriginARM -o OriginARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b OriginARM -o OriginARMSquashed.svg
sol2uml ../src/contracts -hp -s -d 0 -b OriginARM -o OriginARMPublicSquashed.svg
sol2uml storage ../src/contracts,../lib -c OriginARM -o OriginARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap


sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b CapManager -o CapManagerHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b CapManager -o CapManagerSquashed.svg

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b ZapperLidoARM -o ZapperLidoARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b ZapperLidoARM -o ZapperLidoARMSquashed.svg