

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b Proxy -o ProxyHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b Proxy -o ProxySquashed.svg
sol2uml storage ../src/contracts -c Proxy -o ProxyStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b OethARM -o OethARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b OethARM -o OethARMSquashed.svg
sol2uml storage ../src/contracts -c OethARM -o OethARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b LidoOwnerLpARM -o LidoOwnerLpARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b LidoOwnerLpARM -o LidoOwnerLpARMSquashed.svg
sol2uml storage ../src/contracts,../lib -c LidoOwnerLpARM -o LidoOwnerLpARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b LidoMultiLpARM -o LidoMultiLpARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b LidoMultiLpARM -o LidoMultiLpARMSquashed.svg
sol2uml storage ../src/contracts,../lib -c LidoMultiLpARM -o LidoMultiLpARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap
