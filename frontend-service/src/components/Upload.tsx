import {
  ImageKitAbortError,
  ImageKitInvalidRequestError,
  ImageKitServerError,
  ImageKitUploadNetworkError,
  upload,
  type UploadResponse,
} from "@imagekit/react";

import React, {
  useRef,
  useState,
  useImperativeHandle,
  forwardRef,
} from "react";
import { toast } from "sonner";

interface UploadProps {
  children: React.ReactNode;
  type: string;
  setProgress: React.Dispatch<React.SetStateAction<number>>;
  setData: React.Dispatch<React.SetStateAction<UploadResponse | undefined>>;
  onSuccess?: (res: UploadResponse) => void;
  onError?: (err: Error) => void;
}

export interface UploadRef {
  cancelUpload: () => void;
}

const Upload = forwardRef<UploadRef, UploadProps>(
  ({ children, type, setProgress, setData, onSuccess, onError }, ref) => {
    const fileInputRef = useRef<HTMLInputElement>(null);
    const abortControllerRef = useRef<AbortController | null>(null);
    const [loading, setLoading] = useState(false);

    useImperativeHandle(ref, () => ({
      cancelUpload: () => {
        abortControllerRef.current?.abort();
        toast.warning("Upload cancelled");
      },
    }));

    const authenticator = async (): Promise<{
      signature: string;
      expire: string;
      token: string;
      publicKey: string;
    }> => {
      try {
        const response = await fetch(
          `${import.meta.env.VITE_API_URL}/posts/upload-auth`
        );

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(
            `Request failed with status ${response.status}: ${errorText}`
          );
        }

        const { signature, expire, token, publicKey } = await response.json();
        return { signature, expire, token, publicKey };
      } catch (error) {
        console.error("Authentication error:", error);
        throw new Error("Authentication request failed");
      }
    };

    const handleUpload = async () => {
      const fileInput = fileInputRef.current;
      if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
        toast.error("Please select a file to upload.");
        return;
      }

      const file = fileInput.files[0];
      setProgress(0);
      setLoading(true);

      let authParams;
      try {
        authParams = await authenticator();
      } catch (authError) {
        console.error("Failed to authenticate for upload:", authError);
        toast.error("Failed to authenticate upload.");
        setLoading(false);
        return;
      }

      const { signature, expire, token, publicKey } = authParams;
      abortControllerRef.current = new AbortController();

      try {
        const uploadResponse = await upload({
          expire: Number(expire),
          token,
          signature,
          publicKey,
          file,
          fileName: file.name,
          onProgress: (event) => {
            setProgress((event.loaded / event.total) * 100);
          },
          abortSignal: abortControllerRef.current.signal,
        });

        setData(uploadResponse);
        toast.success("Upload successful!");

        onSuccess?.(uploadResponse);
      } catch (error) {
        if (error instanceof ImageKitAbortError) {
          console.error("Upload aborted:", error.reason);
          toast.error(`Upload aborted: ${error.reason}`);
        } else if (error instanceof ImageKitInvalidRequestError) {
          console.error("Invalid request:", error.message);
          toast.error(`Invalid request: ${error.message}`);
        } else if (error instanceof ImageKitUploadNetworkError) {
          console.error("Network error:", error.message);
          toast.error(`Network error: ${error.message}`);
        } else if (error instanceof ImageKitServerError) {
          console.error("Server error:", error.message);
          toast.error(`Server error: ${error.message}`);
        } else {
          console.error("Upload error:", error);
          toast.error(`Upload failed: Unknown error}`);
        }

        if (onError) {
          if (error instanceof Error) {
            onError(error);
          } else {
            onError(new Error(String(error)));
          }
        }
      } finally {
        setLoading(false);
      }
    };

    const getAcceptMimeType = (type: string) => {
      switch (type) {
        case "image":
          return "image/*";
        case "video":
          return "video/*";
        default:
          return "*";
      }
    };

    return (
      <React.Fragment>
        <input
          type="file"
          className="hidden"
          ref={fileInputRef}
          accept={getAcceptMimeType(type)}
          onChange={handleUpload}
        />
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={loading}
          className="cursor-pointer disabled:opacity-50"
        >
          {children}
        </button>
      </React.Fragment>
    );
  }
);

export default Upload;
