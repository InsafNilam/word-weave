import axios from "axios";
import Comment from "./Comment";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth, useUser } from "@clerk/clerk-react";
import { toast } from "sonner";

interface User {
  img?: string;
  username: string;
}

export interface CommentType {
  id: number;
  description: string;
  createdAt: string | Date;
  author: User;
}

const fetchComments = async (postId: number): Promise<CommentType[]> => {
  const res = await axios.get(
    `${import.meta.env.VITE_API_URL}/api/comments/posts/${postId}`
  );
  return res.data.comments;
};

interface CommentsProps {
  postId: number;
}

const Comments = ({ postId }: CommentsProps) => {
  const { user } = useUser();
  const { getToken } = useAuth();

  const { isPending, error, data } = useQuery({
    queryKey: ["comments", postId],
    queryFn: () => fetchComments(postId),
  });

  const queryClient = useQueryClient();

  interface NewComment {
    description: string;
    post_id: number;
  }

  const mutation = useMutation({
    mutationFn: async (newComment: NewComment) => {
      const token = await getToken();
      return axios.post(
        `${import.meta.env.VITE_API_URL}/api/comments`,
        newComment,
        {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        }
      );
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["comments", postId] });
    },
    onError: (error) => {
      toast.error(error.message || "An error occurred");
    },
  });

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);

    const data: NewComment = {
      description: String(formData.get("description") || ""),
      post_id: postId,
    };

    mutation.mutate(data);
  };

  return (
    <div className="flex flex-col gap-8 lg:w-3/5 mb-12">
      <h1 className="text-xl text-gray-500 underline">Comments</h1>
      <form
        onSubmit={handleSubmit}
        className="flex items-center justify-between gap-8 w-full"
      >
        <textarea
          name="description"
          placeholder="Write a comment..."
          className="w-full p-4 rounded-xl"
        />
        <button className="bg-blue-800 px-4 py-3 text-white font-medium rounded-xl">
          Send
        </button>
      </form>
      {isPending ? (
        "Loading..."
      ) : error ? (
        "Error loading comments!"
      ) : (
        <>
          {mutation.isPending && (
            <Comment
              comment={{
                description: `${mutation.variables.description} (Sending...)`,
                createdAt: new Date(),
                author: {
                  img: user?.imageUrl ?? "",
                  username: user?.username ?? "",
                },
              }}
            />
          )}

          {data.map((comment) => (
            <Comment key={comment.id} comment={comment} postId={postId} />
          ))}
        </>
      )}
    </div>
  );
};

export default Comments;
