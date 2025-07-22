import { buildSrc, Video as IKVideo } from '@imagekit/react';

type Props = {
  src: string;
  className?: string;
  w?: number;
  h?: number;
  alt?: string;
};

const Video = ({ src, className, w, h, alt }: Props) => {
  return (
    <IKVideo
      urlEndpoint={import.meta.env.VITE_IK_URL_ENDPOINT}
      src={src}
      controls
      className={className}
      preload="none"
      loading="lazy"
      poster={buildSrc({
        urlEndpoint: import.meta.env.VITE_IK_URL_ENDPOINT,
        src: `${src}/ik-thumbnail.jpg`,
      })}
      alt={alt}
      width={w}
      height={h}
      transformation={[
        {
          width: w,
          height: h,
        },
      ]}
    />
  );
};

export default Video;
