// AIブロック崩し（効果音つき） 2025/08/15
//  効果音：data/hit_brick.mp3, hit_paddle.mp3, hit_ball.mp3
//  操作：Space/クリック開始、M=ボール10個追加、P=ポーズ、R=リスタート、A=AI切替
//       S=効果音ON/OFF、-=音量ダウン、=または+=音量アップ、ESC=終了
//       w パドルサイズ最大/Normal 切替
import ddf.minim.*;

final int Rows = 17;
final int Cols = 34;
final int BrickGap = 2;
final int MarginLR = 16;
final int TopOffset = 80;
final int BallRadius = 8;
final int PaddleH = 12;

// 物理パラメータ
final float BALL_RESTITUTION = 0.98f;
final float PENETRATION_FIX = 0.80f;
final float PENETRATION_SLOP = 0.50f;
final float MAX_BALL_SPEED  = 12.5f;
final float MIN_BALL_SPEED  = 3.5f;

int PaddleW = 140;
int Lives = 3;

boolean widePaddle = false;   // ワイドモードか
int paddleWNormal = 140;      // 通常幅の保持用

// AI
boolean autoPlay = true;
final float AI_PADDLE_VMAX = 250.0f;
final float AI_AIM_BIAS = 0.12f;

// 状態
int level = 1;
boolean stageIntro = true;
boolean[][] alive = new boolean[Rows][Cols];
int bricksRemaining = Rows * Cols;
int score = 0;

// ブロック色（虹色LUT）
int[][] brickColorLUT = new int[Rows][Cols];

// ボール
class Ball { float x,y,vx,vy; Ball(float x,float y,float vx,float vy){this.x=x;this.y=y;this.vx=vx;this.vy=vy;} }
ArrayList<Ball> balls = new ArrayList<Ball>();

float paddleX;
int paddleY;

int brickW, brickH;
boolean paused = false;
boolean gameOver = false;


String toastText = null;
int toastFrames = 0;
int toastColor = 0;

// フォント
PFont hudFont, msgFont;

// 乱数
java.util.Random rng = new java.util.Random();

// ===== Minim（MP3多重再生） =====
Minim minim;
final int SFX_POLY = 8;            // 同時発音数
boolean sfxEnabled = true;
float sfxVolume  = 0.8f;           // 0.0〜1.0（線形）
int   sfxBudgetPerFrame = 6;       // 球-球衝突の1フレーム当たり上限
int   sfxBudget = 0;

AudioPlayer[] plBrick, plPaddle, plBall;
int vBrick=0, vPaddle=0, vBall=0;

void settings(){ size(1000,700); smooth(8); }

void setup(){
  surface.setTitle("New Breakout 2025/08/14 (Minim MP3 SFX)");
  frameRate(60);
  hudFont = createFont("SansSerif.bold", 14, true);
  msgFont = createFont("SansSerif.bold", 28, true);

  computeBrickColors();   // 虹色テーブルを前計算
  loadSFX();              // MP3読み込み

  initLevel(level);
  resetBall(true);
  stageIntro = true;
}

void draw(){
  if(!paused && !gameOver) step();

  background(12,34,110);

  stroke(255,255,255,40);
  for(int r=0;r<Rows;r++){
    for(int c=0;c<Cols;c++){
      if(!alive[r][c]) continue;
      float[] rc = brickRect(r,c);
      fill(brickColorLUT[r][c]);                 // 虹色LUT
      rect(rc[0],rc[1],rc[2]-rc[0],rc[3]-rc[1]);
    }
  }
  noStroke();

  fill(255);
  rect(paddleX,paddleY,PaddleW,PaddleH);

  fill(255,165,0);
  for(Ball b:balls) ellipse(b.x,b.y,BallRadius*2,BallRadius*2);

  // HUD
  fill(255);
  textFont(hudFont);
  textAlign(LEFT,TOP);
  String hud = String.format(
    "Lv:%d   Score:%d   Lives:%d   Balls:%d   Bricks:%d/%d   AI:%s   SFX:%s(%.1f)",
    level, score, Lives, balls.size(), bricksRemaining, Rows*Cols,
    autoPlay ? "ON":"OFF",
    sfxEnabled ? "ON":"OFF", sfxVolume
  );
  text(hud,10,10);

  // トースト
  if(toastFrames>0 && !gameOver) drawCenterText(toastText, toastColor, 230);

  if(gameOver){
    drawCenterText("GAME OVER  -  Press R to restart  /  ESC to quit", color(255,69,0), 255);
  } else if(paused && stageIntro){
    drawCenterText("STAGE " + level + "  -  Click or Space to start", color(0,255,0), 255);
  } else if(paused){
    drawCenterText("PAUSED  -  Click or Space to resume", color(211,211,211), 255);
  }

  // パドル操作
  if(!paused && !gameOver){
    if(autoPlay) autoControl();
    else { paddleX = mouseX - PaddleW/2.0; clampPaddle(); }
  }

  if(toastFrames>0) toastFrames--;
}

void mousePressed(){
  if(paused && !gameOver){ stageIntro=false; paused=false; }
}

void keyPressed(){
  if(keyCode==ESC){ key=0; exit(); return; }
  if(key=='p'||key=='P') paused=!paused;

  if(key=='r'||key=='R'){
    Lives=3; score=0; level=1;
    initLevel(level);
    resetBall(true);
    gameOver=false;
    stageIntro=true;
    toastFrames=0;
  }
  if(key=='w' || key=='W'){
    widePaddle = !widePaddle;
    if(widePaddle){
      PaddleW = width;   // 画面いっぱい
      paddleX = 0;       // 左端に寄せる（はみ出し防止）
      showToast("WIDE PADDLE", 0.8, color(255,255,0));
    }else{
      PaddleW = paddleWNormal; // 通常幅に戻す
      clampPaddle();
      showToast("NORMAL PADDLE", 0.8, color(220));
    }
  }
  if(key==' '){ if(paused && !gameOver){ stageIntro=false; paused=false; } }

  if((key=='m'||key=='M') && !gameOver){ addBalls(10); paused=false; stageIntro=false; }
  if(key=='a'||key=='A') autoPlay=!autoPlay;

  if(key=='s'||key=='S') sfxEnabled=!sfxEnabled;
  if(key=='-') sfxVolume = max(0.0f, sfxVolume-0.1f);
  if(key=='='||key=='+') sfxVolume = min(1.0f, sfxVolume+0.1f);
}

// --- ゲームロジック ---
void initLevel(int lvl){
  // パターン
  int p = (lvl - 1) % 5;     // 0..4 を循環
  applyPattern(p);

  // ブロック総数を数え直し
  bricksRemaining = 0;
  for(int r=0;r<Rows;r++) for(int c=0;c<Cols;c++) if(alive[r][c]) bricksRemaining++;

  updateLayout();
}

void updateLayout(){
  int areaW = width - MarginLR*2 - (Cols-1)*BrickGap;
  int areaH = int(height*0.55) - TopOffset - (Rows-1)*BrickGap;
  brickW = max(6, areaW/Cols);
  brickH = max(10, areaH/Rows);
  paddleY = height - 60;

  // 通常幅を計算して保存し、ワイド状態なら画面幅
  paddleWNormal = (int)max(120, min(240, width/6.0));
  PaddleW = widePaddle ? width : paddleWNormal;

  clampPaddle();
}

void clampPaddle(){ if(paddleX<0) paddleX=0; if(paddleX+PaddleW>width) paddleX=width-PaddleW; }

void resetBall(boolean startPaused){ paused=startPaused; balls.clear(); spawnOneBall(); }
float getBaseSpeed(){ return 7.0; }

void spawnOneBall(){
  float x=paddleX+PaddleW/2.0, y=paddleY-BallRadius-4;
  float speed=getBaseSpeed();
  double ang=-(PI/4.0)-rng.nextDouble()*(PI/2.0);
  float vx=(float)(speed*Math.cos(ang));
  float vy=(float)(speed*Math.sin(ang));
  balls.add(new Ball(x,y,vx,vy));
}

void addBalls(int n){
  for(int i=0;i<n;i++){
    float x=paddleX+PaddleW/2.0+(float)((rng.nextDouble()-0.5)*20.0);
    float y=paddleY-BallRadius-4;
    float speed=getBaseSpeed()+(float)(rng.nextDouble()*1.5);
    double ang=-(PI/4.0)-rng.nextDouble()*(PI/2.0);
    float vx=(float)(speed*Math.cos(ang));
    float vy=(float)(speed*Math.sin(ang));
    balls.add(new Ball(x,y,vx,vy));
  }
}

void step(){
  sfxBudget = sfxBudgetPerFrame;

  for(int i=balls.size()-1;i>=0;i--){
    Ball b=balls.get(i);
    b.x+=b.vx; b.y+=b.vy;

    if(b.x-BallRadius<0){ b.x=BallRadius; b.vx=-b.vx; }
    if(b.x+BallRadius>width){ b.x=width-BallRadius; b.vx=-b.vx; }
    if(b.y-BallRadius<0){ b.y=BallRadius; b.vy=-b.vy; }

    if(b.y-BallRadius>height){ balls.remove(i); continue; }

    // パドル
    if(b.vy>0){
      float lx=paddleX, rx=paddleX+PaddleW, ty=paddleY, by=paddleY+PaddleH;
      int axis=circleRectHitAxis(b.x,b.y,BallRadius,lx,ty,rx,by);
      if(axis!=0){
        b.y=paddleY-BallRadius-0.1f;
        float center=paddleX+PaddleW/2.0;
        float t=(b.x-center)/(PaddleW/2.0); t=constrain(t,-1,1);
        float speed=sqrt(b.vx*b.vx+b.vy*b.vy);
        float angle=t*(PI/3.0);
        b.vx = speed*sin(angle);
        b.vy = -abs(speed*cos(angle));
        float s2=sqrt(b.vx*b.vx+b.vy*b.vy);
        float target=min(11.0, s2+0.15);
        if(s2>0.001){ float k=target/s2; b.vx*=k; b.vy*=k; }
        clampBallSpeed(b);

        playPaddle();  // 効果音
      }
    }

    // ブロック
    boolean hit=false;
    for(int r=0;r<Rows && !hit;r++){
      for(int c=0;c<Cols && !hit;c++){
        if(!alive[r][c]) continue;
        float[] rc=brickRect(r,c);
        int axis=circleRectHitAxis(b.x,b.y,BallRadius,rc[0],rc[1],rc[2],rc[3]);
        if(axis!=0){
          alive[r][c]=false; bricksRemaining--; score+=10;
          if(axis==1) b.vx=-b.vx; else b.vy=-b.vy;
          int nudge=2;
          if(axis==1) b.x += (b.vx==0?1:Math.signum(b.vx))*nudge;
          else        b.y += (b.vy==0?-1:Math.signum(b.vy))*nudge;
          clampBallSpeed(b);

          playBrick();   // 効果音
          hit=true;
        }
      }
    }
  }

  // 球-球
  collideBalls();

  // 消失処理
  if(balls.isEmpty()){
    Lives--;
    if(Lives<=0){ gameOver=true; paused=true; return; }
    resetBall(true);
    stageIntro=false;
    return;
  }

  // 面クリア
  if(bricksRemaining<=0){
    int prev=level;
    level++;
    initLevel(level);
    String pat = patternName((level-1)%5);
    showToast("STAGE "+prev+" CLEAR!  →  STAGE "+level+"  ("+pat+")", 1.5, color(0,255,0));
  }
}

// ---- Utils ----
float[] brickRect(int r,int c){
  float x=MarginLR + c*(brickW+BrickGap);
  float y=TopOffset + r*(brickH+BrickGap);
  return new float[]{x,y,x+brickW,y+brickH};
}

// 0:当たりなし, 1:X反転, 2:Y反転
int circleRectHitAxis(float cx,float cy,float r,float left,float top,float right,float bottom){
  float closestX=constrain(cx,left,right);
  float closestY=constrain(cy,top,bottom);
  float dx=cx-closestX, dy=cy-closestY;
  boolean hit=(dx*dx+dy*dy)<=r*r; if(!hit) return 0;
  float overlapLeft=(cx+r)-left;
  float overlapRight=right-(cx-r);
  float overlapTop=(cy+r)-top;
  float overlapBottom=bottom-(cy-r);
  float minHoriz=min(overlapLeft,overlapRight);
  float minVert =min(overlapTop,overlapBottom);
  return (minHoriz<minVert)?1:2;
}

void showToast(String text,double seconds,int col){
  toastText=text; toastColor=col;
  toastFrames=max(1, round((float)(seconds*frameRate)));
}

void drawCenterText(String s,int col,int alpha_){
  textFont(msgFont); textAlign(LEFT,TOP);
  float tw=textWidth(s); float th=textAscent()+textDescent();
  fill(red(col),green(col),blue(col),alpha_);
  text(s,(width-tw)/2.0,(height-th)/2.0);
}

// === 虹色グラデーション（前計算） ===
void computeBrickColors(){
  colorMode(HSB, 360, 100, 100);
  for (int r = 0; r < Rows; r++){
    for (int c = 0; c < Cols; c++){
      float h = (c * 360.0f) / Cols;
      h = (h + r * (360.0f / Rows) * 0.25f) % 360.0f;  // 行で位相を少しずらす
      float s = 90.0f;
      float b = 95.0f - (r * 25.0f / max(1, Rows - 1)); // 上:明るめ → 下:やや暗め
      brickColorLUT[r][c] = color(h, s, b);
    }
  }
  colorMode(RGB, 255);  // 必ず戻す
}

// === 5種類の配置パターン ===
void applyPattern(int idx){
  // まず全消し
  for(int r=0;r<Rows;r++) for(int c=0;c<Cols;c++) alive[r][c]=false;

  switch(idx % 5){
    case 0: // Solid（全面）
      for(int r=0;r<Rows;r++) for(int c=0;c<Cols;c++) alive[r][c]=true;
      break;

    case 1: // Checker（市松）
      for(int r=0;r<Rows;r++) for(int c=0;c<Cols;c++)
        alive[r][c] = ((r + c) % 2 == 0);
      break;

    case 2: // Border（外枠・太さ2）
      for(int r=0;r<Rows;r++) for(int c=0;c<Cols;c++)
        alive[r][c] = (r < 2 || r >= Rows-2 || c < 2 || c >= Cols-2);
      break;

    case 3: // Diamond（菱形） 正規化マンハッタン距離で決定
      float r0 = (Rows-1)/2.0;
      float c0 = (Cols-1)/2.0;
      for(int r=0;r<Rows;r++){
        for(int c=0;c<Cols;c++){
          float dr = abs(r - r0) / max(1e-6f, r0);
          float dc = abs(c - c0) / max(1e-6f, c0);
          alive[r][c] = (dr + dc <= 1.0);
        }
      }
      break;

    case 4: // Diagonal（斜めストライプ）
      for(int r=0;r<Rows;r++) for(int c=0;c<Cols;c++)
        alive[r][c] = ((r + c) % 4 < 2);   // 45度方向の2列実/2列欠
      break;
  }
}

String patternName(int idx){
  switch(idx % 5){
    case 0: return "Solid";
    case 1: return "Checker";
    case 2: return "Border";
    case 3: return "Diamond";
    case 4: return "Diagonal";
  }
  return "Unknown";
}

// === 衝突 ===
void clampBallSpeed(Ball b){
  float s=sqrt(b.vx*b.vx+b.vy*b.vy);
  if(s<1e-6f) return;
  if(s>MAX_BALL_SPEED){ float k=MAX_BALL_SPEED/s; b.vx*=k; b.vy*=k; }
  else if(s<MIN_BALL_SPEED){ float k=(MIN_BALL_SPEED+1e-4f)/s; b.vx*=k; b.vy*=k; }
}

void collideBalls(){
  int n=balls.size(); if(n<=1) return;
  float sumR=BallRadius*2.0f, sumR2=sumR*sumR;

  for(int i=0;i<n;i++){
    Ball a=balls.get(i);
    for(int k=i+1;k<n;k++){
      Ball b=balls.get(k);
      float dx=b.x-a.x, dy=b.y-a.y;
      float d2=dx*dx+dy*dy; if(d2>sumR2) continue;
      float dist=sqrt(max(1e-12f,d2));
      float nx,ny;
      if(dist>1e-6f){ nx=dx/dist; ny=dy/dist; }
      else { float ang=(float)(rng.nextDouble()*TWO_PI); nx=cos(ang); ny=sin(ang); dist=0; }

      float penetration=(BallRadius*2.0f)-dist;
      if(penetration>PENETRATION_SLOP){
        float corr=(penetration-PENETRATION_SLOP)*PENETRATION_FIX, half=corr*0.5f;
        a.x-=nx*half; a.y-=ny*half;
        b.x+=nx*half; b.y+=ny*half;
      }

      float rvx=b.vx-a.vx, rvy=b.vy-a.vy;
      float relN=rvx*nx+rvy*ny;
      if(relN<0){
        float imp=-(1.0f+BALL_RESTITUTION)*relN/2.0f;
        float ix=imp*nx, iy=imp*ny;
        a.vx-=ix; a.vy-=iy;
        b.vx+=ix; b.vy+=iy;
        clampBallSpeed(a); clampBallSpeed(b);

        float spdN=-relN;
        if(sfxBudget>0 && spdN>1.2f){
          playBallBall();   // 効果音
          sfxBudget--;
        }
      }
    }
  }
}

// === AI ===
void autoControl(){
  float targetCenterX=computeAIMTargetX();
  float center=paddleX+PaddleW/2.0f;
  float err=targetCenterX-center;
  float step=constrain(err,-AI_PADDLE_VMAX,AI_PADDLE_VMAX);
  center+=step; paddleX=center-PaddleW/2.0f; clampPaddle();
}

float computeAIMTargetX(){
  if(balls.isEmpty()) return width*0.5f;
  Ball best=null; float bestT=Float.POSITIVE_INFINITY;
  float yHit=paddleY-BallRadius;

  for(Ball b:balls){
    if(b.vy<=0) continue;
    float t=(yHit-b.y)/b.vy;
    if(t>0 && t<bestT){ bestT=t; best=b; }
  }
  if(best==null){
    float maxY=-1e9f;
    for(Ball b:balls){ if(b.y>maxY){ maxY=b.y; best=b; } }
    bestT=max(0.0f,(yHit-best.y)/max(1e-3f,abs(best.vy)));
  }

  float px=predictXWithBounces(best.x,best.vx,bestT);
  px+=AI_AIM_BIAS*PaddleW*(float)Math.signum(best.vx);
  return constrain(px,BallRadius,width-BallRadius);
}

float predictXWithBounces(float x0,float vx,float t){
  float minX=BallRadius,maxX=width-BallRadius, range=maxX-minX;
  float raw=x0+vx*t; float m=(raw-minX)%(2*range);
  if(m<0) m+=2*range;
  return (m<=range)?(minX+m):(maxX-(m-range));
}

// ===== Minim ユーティリティ =====
void loadSFX(){
  minim = new Minim(this);

  // MP3はストリーミング型の AudioPlayer を使う
  plBrick  = new AudioPlayer[SFX_POLY];
  plPaddle = new AudioPlayer[SFX_POLY];
  plBall   = new AudioPlayer[SFX_POLY];

  for(int i=0;i<SFX_POLY;i++){
    // バッファ小さめでレイテンシ低減（環境で 512〜2048 を調整）
    plBrick[i]  = minim.loadFile("hit_brick.mp3", 1024);
    plPaddle[i] = minim.loadFile("hit_paddle.mp3", 1024);
    plBall[i]   = minim.loadFile("hit_ball.mp3", 1024);

    // 初期ゲイン
    plBrick[i].setGain(lin2db(sfxVolume));
    plPaddle[i].setGain(lin2db(sfxVolume));
    plBall[i].setGain(lin2db(sfxVolume*0.9f));
  }
}

// 線形→dB 変換（AudioPlayer#setGain は dB 指定）
float lin2db(float lin){
  if(lin <= 0.0001f) return -80f;     // ほぼ無音
  return 20f * (float)(Math.log(lin)/Math.log(10.0));
}

// ---- 再生（ピッチ可変なし）----
void playBrick(){
  if(!sfxEnabled) return;
  AudioPlayer p = plBrick[vBrick];
  vBrick = (vBrick+1) % plBrick.length;
  p.rewind();
  p.setGain(lin2db(sfxVolume));
  p.play();
}
void playPaddle(){
  if(!sfxEnabled) return;
  AudioPlayer p = plPaddle[vPaddle];
  vPaddle = (vPaddle+1) % plPaddle.length;
  p.rewind();
  p.setGain(lin2db(sfxVolume));
  p.play();
}
void playBallBall(){
  if(!sfxEnabled) return;
  AudioPlayer p = plBall[vBall];
  vBall = (vBall+1) % plBall.length;
  p.rewind();
  p.setGain(lin2db(sfxVolume*0.9f));
  p.play();
}

void stop(){
  if(plBrick!=null)  for(AudioPlayer p : plBrick)  if(p!=null) p.close();
  if(plPaddle!=null) for(AudioPlayer p : plPaddle) if(p!=null) p.close();
  if(plBall!=null)   for(AudioPlayer p : plBall)   if(p!=null) p.close();
  if(minim!=null) minim.stop();
  super.stop();
}
