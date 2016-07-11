//
//  HapInAVFoundationPlayer.hpp
//  hapVideo64
//
//  Created by Henry Betts on 01/06/2016.
//
//

#ifndef HapInAVFoundationPlayer_h
#define HapInAVFoundationPlayer_h

#include "ofMain.h"

#ifdef __OBJC__
#import "HapInAVFoundationPlayer.h"
#endif

class ofxHapInAVFoundationPlayer : public ofBaseVideoPlayer {
    
public:
    
    ofxHapInAVFoundationPlayer();
    ~ofxHapInAVFoundationPlayer();
	   
    bool load(string name);
    void loadAsync(string name);
    void close();
    void update();
    
    void draw();
    void draw(float x, float y);
    void draw(const ofRectangle & rect);
    void draw(float x, float y, float w, float h);
    
    bool setPixelFormat(ofPixelFormat pixelFormat);
    ofPixelFormat getPixelFormat() const;
    
    void play();
    void stop();
    
    bool isFrameNew() const;
    const ofPixels & getPixels() const;
    ofPixels & getPixels();
    ofTexture * getTexturePtr();
    ofShader * getShaderPtr();
    
    float getWidth() const;
    float getHeight() const;
    
    bool isPaused() const;
    bool isLoaded() const;
    bool isPlaying() const;
    
    float getPosition() const;
    float getSpeed() const;
    float getDuration() const;
    bool getIsMovieDone() const;
    
    void setPaused(bool bPause);
    void setPosition(float pct);
    
    void setLoopState(ofLoopType state);
    void setSpeed(float speed);
    void setFrame(int frame);  // frame 0 = first frame...
    
    int	getCurrentFrame() const;
    int	getTotalNumFrames() const;
    ofLoopType getLoopState() const;
    
    void firstFrame();
    void nextFrame();
    void previousFrame();
    
    ofxHapInAVFoundationPlayer& operator=(ofxHapInAVFoundationPlayer other);
    
    
protected:
    
    bool loadPlayer(string name, bool bAsync);
    void disposePlayer();
    bool isReady() const;
    
#ifdef __OBJC__
    HapInAVFoundationPlayer * videoPlayer;
#else
    void * videoPlayer;
#endif
    
    bool bFrameNew;
    bool bUpdateTexture;
    bool bUpdatePixels;
    
    ofTexture videoTexture;
    ofShader shader;
    ofPixels pixels;
    ofPixelFormat pixelFormat;
    
    int internalFormat;
    
    static const string vertexShader;
    static const string fragmentShader;
    
};


#endif /* HapInAVFoundationPlayer_hpp */
