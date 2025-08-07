https://rubygems.org/

bundle install
gem install <>
gem env
bundle info <>

Many Ruby gems (like json, pg, rbtree, bigdecimal, prism in your case) contain parts written in C or other languages that need to be compiled into executable code for your specific operating system. On Windows, this compilation is typically handled by a set of tools provided by MSYS2 (Minimal SYStem 2).
https://www.msys2.org/

bundle lock --add-platform x86_64-linux

ridk install
pacman -Syu # Updates everything (may prompt to restart MSYS2)
pacman -S base-devel # Installs make, gcc, autoconf, etc.
pacman -S mingw-w64-x86_64-toolchain
pacman -S mingw-w64-x86_64-postgresql # For the 'pg' gem

add env variable C:\msys64\mingw64\bin

#!/bin/bash

grpc_tools_ruby_protoc -I ./protos --ruby_out=./client/lib --grpc_out=./client/lib ./protos/books.proto
grpc_tools_ruby_protoc -I ./protos --ruby_out=./server/lib --grpc_out=./server/lib ./protos/books.proto

grpc_tools_ruby_protoc -I proto --ruby_out=lib/event_service/grpc --grpc_out=lib/event_service/grpc proto/event_service.proto

grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/eventpb --grpc_out=lib/grpc/eventpb protos/event.proto
grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/commentpb --grpc_out=lib/grpc/commentpb protos/comment.proto
grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/eventpb --grpc_out=lib/grpc/eventpb protos/event.proto
grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/eventpb --grpc_out=lib/grpc/eventpb protos/event.proto
grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/eventpb --grpc_out=lib/grpc/eventpb protos/event.proto

ruby bin/server
https://dev.to/torianne02/sequel-an-alternative-to-activerecord-5d6l

docker: error during connect: Head "http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/\_ping": open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.

simply means docker desktop is not running
