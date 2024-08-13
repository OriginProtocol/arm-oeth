
sol2uml ../src/contracts -v -hv -hf -he -hs -hl -b OEthARM -o OEthARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b OEthARM -o OEthARMSquashed.svg
sol2uml storage ../src/contracts -c OEthARM -o OEthARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -b Proxy -o ProxyHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b Proxy -o ProxySquashed.svg
sol2uml storage ../src/contracts -c Proxy -o ProxyStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address
    