https://www.nuget.org/PACKAGES

dotnet tool install --global dotnet-ef
dotnet tool update --global dotnet-ef

dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet add package Microsoft.EntityFrameworkCore.Tools

dotnet add package Pomelo.EntityFrameworkCore.MySql

dotnet ef migrations add InitialCreate
dotnet ef migrations remove

<!-- Some other location -->

dotnet ef migrations add InitialCreate --project CommentService --startup-project CommentService

git rm -r --cached obj/
