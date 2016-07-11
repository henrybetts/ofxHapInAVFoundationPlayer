//
//  ofxHapInAVFoundationPlayer.cpp
//  hapVideo64
//
//  Created by Henry Betts on 01/06/2016.
//
//

#include "ofxHapInAVFoundationPlayer.h"
//#import "HapInAVFoundationPlayer.h"

const string ofxHapInAVFoundationPlayer::vertexShader = "void main(void)\
                                {\
                                gl_Position = ftransform();\
                                gl_TexCoord[0] = gl_TextureMatrix[0] * gl_MultiTexCoord0;\
                                }";

const string ofxHapInAVFoundationPlayer::fragmentShader = "uniform sampler2D cocgsy_src;\
                                const vec4 offsets = vec4(-0.50196078431373, -0.50196078431373, 0.0, 0.0);\
                                void main()\
                                {\
                                vec4 CoCgSY = texture2D(cocgsy_src, gl_TexCoord[0].xy);\
                                CoCgSY += offsets;\
                                float scale = ( CoCgSY.z * ( 255.0 / 8.0 ) ) + 1.0;\
                                float Co = CoCgSY.x / scale;\
                                float Cg = CoCgSY.y / scale;\
                                float Y = CoCgSY.w;\
                                vec4 rgba = vec4(Y + Co - Cg, Y + Cg, Y - Co - Cg, 1.0);\
                                gl_FragColor = rgba;\
                                }";

//--------------------------------------------------------------
ofxHapInAVFoundationPlayer::ofxHapInAVFoundationPlayer() {
    videoPlayer = nullptr;
    bFrameNew = false;
    bUpdateTexture = false;
    bUpdatePixels = false;
    pixelFormat = OF_PIXELS_RGBA;
}

//--------------------------------------------------------------
ofxHapInAVFoundationPlayer::~ofxHapInAVFoundationPlayer() {
    disposePlayer();
}

//--------------------------------------------------------------
ofxHapInAVFoundationPlayer& ofxHapInAVFoundationPlayer::operator=(ofxHapInAVFoundationPlayer other)
{

    videoTexture.clear();
    pixels.clear();
    
    bFrameNew = false;
    bUpdateTexture = false;
    bUpdatePixels = false;
    
    std::swap(videoPlayer, other.videoPlayer);
    return *this;
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::loadAsync(string name){
    loadPlayer(name, true);
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::load(string name) {
    return loadPlayer(name, false);
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::loadPlayer(string name, bool bAsync) {
    
    NSString * videoPath = [NSString stringWithUTF8String:name.c_str()];
    NSString * videoLocalPath = [NSString stringWithUTF8String:ofToDataPath(name).c_str()];
    
    BOOL bStream = NO;
    
    bStream = bStream || (ofIsStringInString(name, "http://"));
    bStream = bStream || (ofIsStringInString(name, "https://"));
    bStream = bStream || (ofIsStringInString(name, "rtsp://"));
    
    NSURL * url = nil;
    if(bStream == YES) {
        url = [NSURL URLWithString:videoPath];
    } else {
        url = [NSURL fileURLWithPath:videoLocalPath];
    }
    
    bFrameNew = false;
    bUpdateTexture = true;
    bUpdatePixels = true;
    
    bool bLoaded = false;
    
    if(videoPlayer == nullptr) {
        // create a new player if its not allocated
        videoPlayer = [[HapInAVFoundationPlayer alloc] init];
    }
    
    bLoaded = [videoPlayer loadWithURL:url async:bAsync];
    
    videoTexture.clear();
    pixels.clear();
    
    return bLoaded;
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::disposePlayer() {
    
    if (videoPlayer != nullptr) {
        
        videoTexture.clear();
        pixels.clear();
        shader.unload();
        
        // dispose videoplayer
        __block HapInAVFoundationPlayer *currentPlayer = videoPlayer;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @autoreleasepool {
                [currentPlayer unloadVideo]; // synchronious call to unload video
                [currentPlayer autorelease]; // release
            }
        });
        
        videoPlayer = nullptr;
    }
    
    
    bFrameNew = false;
    bUpdateTexture = false;
    bUpdatePixels = false;
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::close() {
    if(videoPlayer != nullptr) {
        
        videoTexture.clear();
        pixels.clear();
        shader.unload();
        
        [videoPlayer close];
    }
    
    bFrameNew = false;
    bUpdateTexture = false;
    bUpdatePixels = false;

}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::setPixelFormat(ofPixelFormat value) {
    pixelFormat = value;
    bUpdatePixels = true;
    return true;
}

//--------------------------------------------------------------
ofPixelFormat ofxHapInAVFoundationPlayer::getPixelFormat() const{
    return pixelFormat;
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::update() {
    
    bFrameNew = false; // default.
    
    if(!isLoaded() || !isReady()) {
        return;
    }
    
    [videoPlayer update];
    bFrameNew = [videoPlayer isNewFrame]; // check for new frame staright after the call to update.
    
    if(bFrameNew) {
        /**
         *  mark pixels to be updated.
         *  pixels are then only updated if the getPixels() method is called,
         *  internally or externally to this class.
         *  this ensures the pixels are updated only once per frame.
         */
        bUpdateTexture = true;
        bUpdatePixels = true;
    }
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::draw() {
    draw(0, 0);
}

void ofxHapInAVFoundationPlayer::draw(float x, float y) {
    draw(x, y, getWidth(), getHeight());
}

void ofxHapInAVFoundationPlayer::draw(const ofRectangle & rect) {
    draw(rect.x, rect.y, rect.width, rect.height);
}

void ofxHapInAVFoundationPlayer::draw(float x, float y, float w, float h) {
    if(isLoaded() && isReady()) {
        
        ofTexture* tex = getTexturePtr();
        
        if (tex && tex->isAllocated()){
            
            if (internalFormat == HapTextureFormat_RGBA_DXT5)
                getShaderPtr()->begin();
            
            tex->draw(x,y,w,h);
            
            if (internalFormat == HapTextureFormat_RGBA_DXT5)
                getShaderPtr()->end();
            
        }
        
    }
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::play() {
    if(videoPlayer == nullptr) {
        ofLogWarning("ofxHapInAVFoundationPlayer") << "play(): video not loaded.";
        return;
    }
    
    [videoPlayer play];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::stop() {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer pause];
    [videoPlayer setPosition:0];
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::isFrameNew() const {
    if(videoPlayer != nullptr) {
        return bFrameNew;
    }
    return false;
}

//--------------------------------------------------------------
const ofPixels & ofxHapInAVFoundationPlayer::getPixels() const {
    return const_cast<ofxHapInAVFoundationPlayer *>(this)->getPixels();
}

ofPixels & ofxHapInAVFoundationPlayer::getPixels() {
    
    if(isLoaded() == false) {
        return pixels;
    }
    
    if(bUpdatePixels == false) {
        // if pixels have not changed,
        // return the already calculated pixels.
        return pixels;
    }
    
    ofFbo fbo;
    fbo.allocate(getWidth(), getHeight(), ofGetGLInternalFormatFromPixelFormat(pixelFormat));
    
    fbo.begin();
    draw();
    fbo.end();
    
    fbo.readToPixels(pixels);
    fbo.clear();
    
    bUpdatePixels = false;
    
    return pixels;
    
}

//--------------------------------------------------------------
ofTexture * ofxHapInAVFoundationPlayer::getTexturePtr() {
    
    
    if(isLoaded() == false || isReady() == false) {
        return &videoTexture;
    }
    
    if(bUpdateTexture == false) {
        return &videoTexture;
    }
    
    HapDecoderFrame* frame = videoPlayer.currentFrame;
    
    if (frame != nil){
        
        int bitsPerPixel;
        
        switch (frame.dxtPixelFormats[0]) {
            case kHapCVPixelFormat_RGB_DXT1:
                internalFormat = HapTextureFormat_RGB_DXT1;
                bitsPerPixel = 4;
                break;
            case kHapCVPixelFormat_RGBA_DXT5:
            case kHapCVPixelFormat_YCoCg_DXT5:
                internalFormat = HapTextureFormat_RGBA_DXT5;
                bitsPerPixel = 8;
                break;
            default:
                ofLogError("ofxHapInAVFoundationPlayer", "Unrecognized pixel format.");
                return &videoTexture;
                break;
        }
        
        int bytesPerRow = (frame.dxtImgSize.width * bitsPerPixel) / 8;
        int newDataSize = bytesPerRow * frame.dxtImgSize.height;
        
        if (!videoTexture.isAllocated()){
            
            ofTextureData texData;
            texData.width = frame.dxtImgSize.width;
            texData.height = frame.dxtImgSize.height;
            texData.textureTarget = GL_TEXTURE_2D;
            texData.glInternalFormat = internalFormat;
            
            videoTexture.allocate(texData, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV);
            
            videoTexture.bind();
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_STORAGE_HINT_APPLE , GL_STORAGE_SHARED_APPLE);
            videoTexture.unbind();
        }
        
        glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
        glEnable(GL_TEXTURE_2D);
        
        ofTextureData &texData = videoTexture.getTextureData();
        glBindTexture(GL_TEXTURE_2D, texData.textureID);
        
        glTextureRangeAPPLE(GL_TEXTURE_2D, newDataSize, frame.dxtDatas[0]);
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
        
        glCompressedTexSubImage2D(GL_TEXTURE_2D,
                                  0,
                                  0,
                                  0,
                                  frame.dxtImgSize.width,
                                  frame.dxtImgSize.height,
                                  internalFormat,
                                  newDataSize,
                                  frame.dxtDatas[0]);
        
        glPopClientAttrib();
        glDisable(GL_TEXTURE_2D);
        
    }
    
    bUpdateTexture = false;
    
    return &videoTexture;
}

ofShader* ofxHapInAVFoundationPlayer::getShaderPtr(){
    
    if (!shader.isLoaded()){
        
        shader.setupShaderFromSource(GL_VERTEX_SHADER, ofxHapInAVFoundationPlayer::vertexShader);
        shader.setupShaderFromSource(GL_FRAGMENT_SHADER, ofxHapInAVFoundationPlayer::fragmentShader);
        shader.bindDefaults();
        shader.linkProgram();
        
    }
    
    return &shader;
    
}


//--------------------------------------------------------------
float ofxHapInAVFoundationPlayer::getWidth() const {
    if(videoPlayer == nullptr) {
        return 0;
    }
    
    return [videoPlayer getWidth];
}

//--------------------------------------------------------------
float ofxHapInAVFoundationPlayer::getHeight() const {
    if(videoPlayer == nullptr) {
        return 0;
    }
    
    return [videoPlayer getHeight];
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::isPaused() const {
    if(videoPlayer == nullptr) {
        return false;
    }
    
    return ![videoPlayer isPlaying];
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::isLoaded() const {
    if(videoPlayer == nullptr) {
        return false;
    }
    
    return [videoPlayer isLoaded];
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::isReady() const {
    if(videoPlayer == nullptr) {
        return false;
    }
    
    return [videoPlayer isReady];
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::isPlaying() const {
    if(videoPlayer == nullptr) {
        return false;
    }
    
    return [videoPlayer isPlaying];
}

//--------------------------------------------------------------
float ofxHapInAVFoundationPlayer::getPosition() const {
    if(videoPlayer == nullptr) {
        return 0;
    }
    
    return [videoPlayer getPosition];
}

//--------------------------------------------------------------
float ofxHapInAVFoundationPlayer::getSpeed() const {
    if(videoPlayer == nullptr) {
        return 0;
    }
    
    return [videoPlayer getSpeed];
}

//--------------------------------------------------------------
float ofxHapInAVFoundationPlayer::getDuration() const {
    if(videoPlayer == nullptr) {
        return 0;
    }
    
    return [videoPlayer getDurationInSec];
}

//--------------------------------------------------------------
bool ofxHapInAVFoundationPlayer::getIsMovieDone() const {
    if(videoPlayer == nullptr) {
        return false;
    }
    
    return [videoPlayer isFinished];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::setPaused(bool bPause) {
    if(videoPlayer == nullptr) {
        return;
    }
    
    if(bPause) {
        [videoPlayer pause];
    } else {
        [videoPlayer play];
    }
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::setPosition(float pct) {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer setPosition:pct];
}


//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::setLoopState(ofLoopType state) {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer setLoop:(HapInAVFoundationPlayerLoopType)state];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::setSpeed(float speed) {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer setSpeed:speed];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::setFrame(int frame) {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer setFrame:frame];
}

//--------------------------------------------------------------
int	ofxHapInAVFoundationPlayer::getCurrentFrame() const {
    if(videoPlayer == nullptr){
        return 0;
    }
    return [videoPlayer getCurrentFrameNum];
}

//--------------------------------------------------------------
int	ofxHapInAVFoundationPlayer::getTotalNumFrames() const {
    if(videoPlayer == nullptr){
        return 0;
    }
    return [videoPlayer getDurationInFrames];
}

//--------------------------------------------------------------
ofLoopType	ofxHapInAVFoundationPlayer::getLoopState() const {
    if(videoPlayer == nullptr) {
        return OF_LOOP_NONE;
    }
    
    return (ofLoopType)[videoPlayer getLoop];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::firstFrame() {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer setPosition:0];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::nextFrame() {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer stepByCount:1];
}

//--------------------------------------------------------------
void ofxHapInAVFoundationPlayer::previousFrame() {
    if(videoPlayer == nullptr) {
        return;
    }
    
    [videoPlayer stepByCount:-1];
    
}

