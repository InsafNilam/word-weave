import PostListItem from "./PostListItem";
import { useInfiniteQuery } from "@tanstack/react-query";
import axios from "axios";
import { useSearchParams } from "react-router-dom";
import { FixedSizeList as List } from "react-window";
import InfiniteLoader from "react-window-infinite-loader";
import type { ListChildComponentProps } from "react-window";

interface Post {
  _id: string;
  title: string;
  img?: string;
  slug: string;
  desc: string;
  createdAt: string;
  updatedAt: string;
  category: string;
  user: {
    username: string;
  };
  [key: string]: unknown;
}

interface FetchPostsResponse {
  posts: Post[];
  hasMore: boolean;
  [key: string]: unknown;
}

const fetchPosts = async (
  page: number,
  searchParams: URLSearchParams
): Promise<FetchPostsResponse> => {
  const searchParamsObj: Record<string, string> = Object.fromEntries([...searchParams]);

  console.log(searchParamsObj);

  const res = await axios.get<FetchPostsResponse>(`${import.meta.env.VITE_API_URL}/posts`, {
    params: { page: page, limit: 10, ...searchParamsObj },
  });
  return res.data;
};

const PostList = () => {
  const [searchParams] = useSearchParams();

  const {
    data,
    error,
    fetchNextPage,
    hasNextPage,
    isFetching,
    isFetchingNextPage,
  } = useInfiniteQuery({
    queryKey: ["posts", searchParams.toString()],
    queryFn: ({ pageParam = 1 }) => fetchPosts(pageParam, searchParams),
    initialPageParam: 1,
    getNextPageParam: (lastPage, pages) =>
      lastPage.hasMore ? pages.length + 1 : undefined,
  });


  // if (status === "loading") return "Loading...";
  if (isFetching) return "Loading...";


  // if (status === "error") return "Something went wrong!";
  if (error) return "Something went wrong!";

  const items = data?.pages?.flatMap((page) => page.posts) || [];
  const itemCount = hasNextPage ? items.length + 1 : items.length;

  const isItemLoaded = (index: number) => !hasNextPage || index < items.length;

  const Row = ({ index, style }: ListChildComponentProps) => {
    if (!isItemLoaded(index)) {
      return <div style={style}>Loading...</div>; // or a Skeleton
    }

    const post = items[index];

    if (!post) {
      return null;
    }

    return (
      <div style={style}>
        <PostListItem post={post} />
      </div>
    );
  };

  return (
    <InfiniteLoader
      isItemLoaded={isItemLoaded}
      itemCount={itemCount}
      loadMoreItems={async () => {
        if (isFetchingNextPage || !hasNextPage) return;
        await fetchNextPage();
      }}
    >
      {({ onItemsRendered, ref }) => (
        <List
          height={window.innerHeight}
          itemCount={items.length}
          itemSize={600}
          onItemsRendered={onItemsRendered}
          ref={ref}
          width={450}
        >
          {Row}
        </List>
      )}
    </InfiniteLoader>
  );
};

export default PostList;
