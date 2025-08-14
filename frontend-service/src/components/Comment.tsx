import { format } from "timeago.js";
import Image from "./Image";
import { useAuth, useUser } from "@clerk/clerk-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import axios from "axios";
import { toast } from "sonner";

type CommentUser = {
  img?: string;
  username: string;
};

type CommentType = {
  id?: number;
  author?: CommentUser;
  createdAt: string | Date;
  description: string;
};

interface CommentProps {
  comment: CommentType;
  postId?: number;
}

const Comment = ({ comment, postId }: CommentProps) => {
  const { user } = useUser();
  const { getToken } = useAuth();
  const role = user?.publicMetadata?.role;

  const queryClient = useQueryClient();

  const mutation = useMutation({
    mutationFn: async () => {
      const token = await getToken();
      return axios.delete(
        `${import.meta.env.VITE_API_URL}/api/comments/${comment.id}`,
        {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        }
      );
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["comments", postId] });
      toast.success("Comment deleted successfully");
    },
    onError: (error) => {
      toast.error(error.message || "An error occurred");
    },
  });

  return (
    <div className="p-4 bg-slate-50 rounded-xl mb-8">
      <div className="flex items-center gap-4">
        {comment?.author?.img && (
          <Image
            src={comment?.author?.img}
            className="w-10 h-10 rounded-full object-cover"
            w={40}
          />
        )}
        <span className="font-medium">{comment?.author?.username}</span>
        <span className="text-sm text-gray-500">
          {format(comment.createdAt)}
        </span>
        {user &&
          (comment?.author?.username === user.username || role === "admin") && (
            <span
              className="text-xs text-red-300 hover:text-red-500 cursor-pointer"
              onClick={() => mutation.mutate()}
            >
              delete
              {mutation.isPending && <span>(in progress)</span>}
            </span>
          )}
      </div>
      <div className="mt-4">
        <p>{comment.description}</p>
      </div>
    </div>
  );
};

export default Comment;
