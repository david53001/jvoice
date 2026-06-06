import { Composition } from "remotion";
import { JVoiceDemo } from "./JVoiceDemo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="JVoiceDemo"
      component={JVoiceDemo}
      durationInFrames={600}
      fps={30}
      width={1600}
      height={1000}
    />
  );
};
