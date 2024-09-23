

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

sol2uml ../src/contracts -v -hv -hf -he -hs -hl -hi -b LidoFixedPriceMultiLpARM -o LidoFixedPriceMultiLpARMHierarchy.svg
sol2uml ../src/contracts -s -d 0 -b LidoFixedPriceMultiLpARM -o LidoFixedPriceMultiLpARMSquashed.svg
sol2uml ../src/contracts -hp -s -d 0 -b LidoFixedPriceMultiLpARM -o LidoFixedPriceMultiLpARMPublicSquashed.svg
sol2uml storage ../src/contracts,../lib -c LidoFixedPriceMultiLpARM -o LidoFixedPriceMultiLpARMStorage.svg \
    -sn eip1967.proxy.implementation,eip1967.proxy.admin \
    -st address,address \
    --hideExpand gap,_gap
