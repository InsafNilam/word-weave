import React from "react";
import { useAuth, useUser } from "@clerk/clerk-react";
import "react-quill-new/dist/quill.snow.css";
import ReactQuill from "react-quill-new";
import { useMutation } from "@tanstack/react-query";
import axios from "axios";
import { useNavigate } from "react-router-dom";
import Upload from "../components/Upload";
import { toast } from "sonner";
import { type UploadResponse } from "@imagekit/react";

type NewPost = {
  img: string;
  title: FormDataEntryValue | null;
  category: FormDataEntryValue | null;
  desc: FormDataEntryValue | null;
  content: string;
};

interface HandleSubmitEvent extends React.FormEvent<HTMLFormElement> {
  target: EventTarget & HTMLFormElement;
}

const CATEGORIES = [
  { value: 'general', label: 'General' },
  { value: 'web-design', label: 'Web Design' },
  { value: 'development', label: 'Development' },
  { value: 'databases', label: 'Databases' },
  { value: 'seo', label: 'Search Engines' },
  { value: 'marketing', label: 'Marketing' },
] as const;

const Write: React.FC = () => {
  const { isLoaded, isSignedIn } = useUser();
  const { getToken } = useAuth();
  const navigate = useNavigate();

  // Form state
  const [title, setTitle] = React.useState<string>('');
  const [category, setCategory] = React.useState<string>('general');
  const [description, setDescription] = React.useState<string>('');
  const [content, setContent] = React.useState<string>('');

  // Upload state
  const [cover, setCover] = React.useState<UploadResponse | undefined>(undefined);
  const [img, setImg] = React.useState<UploadResponse | undefined>(undefined);
  const [video, setVideo] = React.useState<UploadResponse | undefined>(undefined);
  const [progress, setProgress] = React.useState<number>(0);

  // Validation state
  const [errors, setErrors] = React.useState<Record<string, string>>({});

  // Insert image into content when uploaded
  React.useEffect(() => {
    if (img) {
      setContent(prev => prev + `<p><img src="${img.url}" alt="Uploaded image" style="max-width: 100%; height: auto;" /></p>`);
    }
  }, [img]);

  // Insert video into content when uploaded
  React.useEffect(() => {
    if (video) {
      setContent(prev => prev + `<p><iframe class="ql-video" src="${video.url}" title="Uploaded video"></iframe></p>`);
    }
  }, [video]);

  // Form validation
  const validateForm = React.useCallback(() => {
    const newErrors: Record<string, string> = {};

    if (!title.trim()) {
      newErrors.title = 'Title is required';
    } else if (title.length > 200) {
      newErrors.title = 'Title must be less than 200 characters';
    }

    if (!description.trim()) {
      newErrors.description = 'Description is required';
    } else if (description.length > 500) {
      newErrors.description = 'Description must be less than 500 characters';
    }

    if (!content.trim() || content === '<p><br></p>') {
      newErrors.content = 'Content is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [title, description, content]);

  // Create post mutation
  const mutation = useMutation({
    mutationFn: async (newPost: NewPost) => {
      const token = await getToken();
      return axios.post(`${import.meta.env.VITE_API_URL}/api/posts`, newPost, {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });
    },
    onSuccess: (res) => {
      toast.success('Post has been created successfully!');
      navigate(`/${res.data.post.slug}`);
      // Clear form
      resetForm();
    },
    onError: (error: unknown) => {
      let errorMessage = 'Failed to create post';
      if (typeof error === 'object' && error !== null) {
        if ('response' in error && typeof (error as { response?: object }).response === 'object') {
          const response = (error as { response?: { data?: { message?: string } } }).response;
          if (response?.data?.message) {
            errorMessage = response.data.message;
          }
        } else if ('message' in error && typeof (error as { message?: string }).message === 'string') {
          errorMessage = (error as { message: string }).message;
        }
      }
      toast.error(errorMessage);
      console.error('Post creation error:', error);
    },
  });

  // Reset form function
  const resetForm = React.useCallback(() => {
    setTitle('');
    setCategory('general');
    setDescription('');
    setContent('');
    setCover(undefined);
    setImg(undefined);
    setVideo(undefined);
    setProgress(0);
    setErrors({});
  }, []);

  // Handle form submission
  const handleSubmit = React.useCallback((e: HandleSubmitEvent) => {
    e.preventDefault();

    if (!validateForm()) {
      toast.error('Please fix the errors before submitting');
      return;
    }

    const data: NewPost = {
      img: cover?.filePath || '',
      title: title.trim(),
      category,
      desc: description.trim(),
      content,
    };

    mutation.mutate(data);
  }, [title, category, description, content, cover, validateForm, mutation]);

  // Loading states
  if (!isLoaded) {
    return (
      <div className="h-[calc(100vh-64px)] md:h-[calc(100vh-80px)] flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-800 mx-auto mb-4"></div>
          <p className="text-gray-600">Loading...</p>
        </div>
      </div>
    );
  }

  if (isLoaded && !isSignedIn) {
    return (
      <div className="h-[calc(100vh-64px)] md:h-[calc(100vh-80px)] flex items-center justify-center">
        <div className="text-center p-8 bg-white rounded-xl shadow-md">
          <h2 className="text-2xl font-semibold mb-4 text-gray-800">Authentication Required</h2>
          <p className="text-gray-600 mb-6">You need to sign in to create a post.</p>
          <button
            onClick={() => navigate('/sign-in')}
            className="bg-blue-800 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors"
          >
            Sign In
          </button>
        </div>
      </div>
    );
  }

  const isUploading = 0 < progress && progress < 100;
  const isSubmitting = mutation.isPending;
  const isDisabled = isUploading || isSubmitting;

  return (
    <div className="h-[calc(100vh-64px)] md:h-[calc(100vh-80px)] flex flex-col gap-6 p-4 max-w-4xl mx-auto">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-light text-gray-800">Create a New Post</h1>
        <button
          type="button"
          onClick={resetForm}
          className="text-sm text-gray-500 hover:text-gray-700 underline"
          disabled={isDisabled}
        >
          Clear All
        </button>
      </div>

      <form onSubmit={handleSubmit} className="flex flex-col gap-6 flex-1 mb-6">
        {/* Cover Image Upload */}
        <div className="space-y-2">
          <Upload type="image" setProgress={setProgress} setData={setCover}>
            <button
              type="button"
              className="w-max p-3 shadow-md rounded-xl text-sm text-gray-600 bg-white hover:bg-gray-50 transition-colors border border-gray-200"
              disabled={isDisabled}
            >
              {cover ? '✅ Cover image added' : '📸 Add a cover image'}
            </button>
          </Upload>
          {cover && (
            <div className="relative w-full max-w-md">
              <img
                src={cover.url}
                alt="Cover preview"
                className="w-full h-32 object-cover rounded-lg border"
              />
              <button
                type="button"
                onClick={() => setCover(undefined)}
                className="absolute top-2 right-2 bg-red-500 text-white rounded-full w-6 h-6 flex items-center justify-center text-xs hover:bg-red-600"
                disabled={isDisabled}
              >
                ×
              </button>
            </div>
          )}
        </div>

        {/* Title Input */}
        <div className="space-y-2">
          <input
            className={`w-full text-4xl font-semibold bg-transparent outline-none border-b-2 pb-2 transition-colors ${errors.title ? 'border-red-500' : 'border-gray-200 focus:border-blue-500'
              }`}
            type="text"
            placeholder="My Awesome Story"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            disabled={isDisabled}
            maxLength={200}
          />
          {errors.title && <p className="text-red-500 text-sm">{errors.title}</p>}
          <p className="text-xs text-gray-500">{title.length}/200 characters</p>
        </div>

        {/* Category Selection */}
        <div className="flex items-center gap-4">
          <label htmlFor="category" className="text-sm font-medium text-gray-700">
            Choose a category:
          </label>
          <select
            id="category"
            name="category"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="p-2 rounded-xl bg-white shadow-md border border-gray-200 focus:outline-none focus:ring-2 focus:ring-blue-500"
            disabled={isDisabled}
          >
            {CATEGORIES.map(({ value, label }) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>

        {/* Description */}
        <div className="space-y-2">
          <textarea
            className={`w-full p-4 rounded-xl bg-white shadow-md border transition-colors resize-none ${errors.description ? 'border-red-500' : 'border-gray-200 focus:border-blue-500'
              }`}
            name="desc"
            placeholder="A short description of your post..."
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={isDisabled}
            rows={3}
            maxLength={500}
          />
          {errors.description && <p className="text-red-500 text-sm">{errors.description}</p>}
          <p className="text-xs text-gray-500">{description.length}/500 characters</p>
        </div>

        {/* Content Editor */}
        <div className="flex flex-1 gap-4">
          <div className="flex flex-col gap-1">
            <Upload type="image" setProgress={setProgress} setData={setImg}>
              <button
                type="button"
                className="p-0 text-xl hover:bg-gray-100 rounded-lg transition-colors border border-gray-200"
                disabled={isDisabled}
                title="Add image to content"
              >
                🌆
              </button>
            </Upload>
            <Upload type="video" setProgress={setProgress} setData={setVideo}>
              <button
                type="button"
                className="p-0 text-xl hover:bg-gray-100 rounded-lg transition-colors border border-gray-200"
                disabled={isDisabled}
                title="Add video to content"
              >
                ▶️
              </button>
            </Upload>
          </div>

          <div className="flex-1 space-y-2">
            <ReactQuill
              theme="snow"
              className="flex-1 rounded-xl bg-white shadow-md"
              value={content}
              onChange={setContent}
              readOnly={isDisabled}
              placeholder="Start writing your amazing content here..."
              modules={{
                toolbar: [
                  [{ 'header': [1, 2, 3, false] }],
                  ['bold', 'italic', 'underline', 'strike'],
                  [{ 'list': 'ordered' }, { 'list': 'bullet' }],
                  ['blockquote', 'code-block'],
                  ['link'],
                  ['clean']
                ],
              }}
            />
            {errors.content && <p className="text-red-500 text-sm">{errors.content}</p>}
          </div>
        </div>

        {/* Upload Progress */}
        {progress > 0 && (
          <div className="space-y-2">
            <div className="flex items-center justify-between text-sm text-gray-600">
              <span>Upload Progress</span>
              <span>{Math.round(progress)}%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2">
              <div
                className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                style={{ width: `${progress}%` }}
              ></div>
            </div>
          </div>
        )}

        {/* Submit Button */}
        <div className="flex items-center justify-between pt-4 border-t border-gray-200">
          <div className="text-sm text-gray-500">
            {mutation.isError && (
              <span className="text-red-500">❌ Error creating post</span>
            )}
          </div>

          <button
            type="submit"
            disabled={isDisabled}
            className="bg-blue-800 text-white font-medium rounded-xl px-8 py-3 transition-colors disabled:bg-blue-400 disabled:cursor-not-allowed hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            {isSubmitting ? (
              <span className="flex items-center gap-2">
                <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                Creating...
              </span>
            ) : (
              'Create Post'
            )}
          </button>
        </div>
      </form>
    </div>
  );
};

export default Write;
