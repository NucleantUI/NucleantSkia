# Make Github action

make a github action that is triggered on each new tag

* builds skia for all the platforms.. (matrix)
but here is where we need them as zipped assets that is attached to each release
soo it must get checksum of each and then i guess make a new commit with 
binary targets using right checksum for each url

i guess for non apple platforms, we now need zipped arfifactbundles

for now still keep the current Dependencies in Master
but can we somehow do sooo Dependecies is not included in the release ?
and later we can ditch them since master will just use last release deps...



