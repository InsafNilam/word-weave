import { Outlet } from "react-router-dom";
import Navbar from "@/components/Navbar";

const AppLayout = () => {
  return (
    <div className="px-4 md:px-8 lg:px-16">
      <Navbar />
      <Outlet />
    </div>
  );
};

export default AppLayout;
